defmodule AOS.AgentOS.Core.Nodes.PanelDebate do
  @moduledoc """
  Runs a structured multi-persona debate and synthesizes the final conclusion.
  """

  @behaviour AOS.AgentOS.Core.Node

  alias AOS.AgentOS.Roles.LLM

  require Logger

  @default_max_rounds 3
  @default_consensus_threshold 1.0

  @default_personas [
    %{
      name: "historian",
      discipline: "Historian",
      instructions:
        "Analyze the topic through historical precedent, long-term change, institutional memory, and source limitations."
    },
    %{
      name: "statistician",
      discipline: "Statistician",
      instructions:
        "Analyze the topic through measurement quality, base rates, uncertainty, causal identification, and statistical evidence."
    },
    %{
      name: "sociologist",
      discipline: "Sociologist",
      instructions:
        "Analyze the topic through institutions, social stratification, norms, group behavior, and structural incentives."
    },
    %{
      name: "psychologist",
      discipline: "Psychologist",
      instructions:
        "Analyze the topic through cognition, motivation, emotion, behavioral biases, and individual-level mechanisms."
    },
    %{
      name: "economist",
      discipline: "Economist",
      instructions:
        "Analyze the topic through incentives, trade-offs, constraints, market or policy mechanisms, and opportunity costs."
    }
  ]

  @impl true
  def run(context, _opts) do
    topic = Map.get(context, :panel_topic) || Map.get(context, :task) || "No topic provided"
    personas = panel_personas(context)
    llm = Map.get(context, :panel_llm, &LLM.call_with_meta/2)
    max_rounds = panel_max_rounds(context)

    Logger.info("[PanelDebate] Running panel debate with #{length(personas)} persona(s).")

    notify_panel(context, :started, %{topic: topic, personas: Enum.map(personas, & &1.discipline)})

    with {:ok, positions, first_meta} <- initial_positions(personas, topic, context, llm),
         {:ok, debate_state, debate_meta} <-
           run_revision_rounds(personas, topic, positions, context, llm, max_rounds),
         {:ok, conclusion, synthesis_meta} <-
           synthesize_conclusion(topic, positions, debate_state, context, llm) do
      debate = %{
        topic: topic,
        personas: Enum.map(personas, &Map.take(&1, [:name, :discipline])),
        initial_positions: positions,
        revision_rounds: debate_state.rounds,
        consensus: debate_state.consensus,
        stop_reason: debate_state.stop_reason,
        revised_positions: debate_state.final_positions,
        conclusion: conclusion
      }

      {:ok,
       context
       |> Map.put(:panel_debate, debate)
       |> Map.put(:result, conclusion)
       |> Map.put(:last_outcome, :success)
       |> accumulate_meta(first_meta)
       |> accumulate_meta(debate_meta)
       |> accumulate_meta(synthesis_meta)}
    end
  end

  def default_personas, do: @default_personas

  defp initial_positions(personas, topic, context, llm) do
    call_personas(personas, context, llm, :initial_position, 0, fn persona ->
      """
      You are participating in an expert panel debate.

      Topic:
      #{topic}

      Persona:
      #{persona.discipline} (#{persona.name})

      Persona instructions:
      #{persona.instructions}

      Round 1 task:
      Present your initial position in Markdown with these sections:
      - Core claim
      - Key evidence or reasoning
      - Main uncertainty
      - What other disciplines should challenge

      Be rigorous, explicit about uncertainty, and avoid pretending to have evidence you do not have.
      """
    end)
  end

  defp run_revision_rounds(personas, topic, positions, context, llm, max_rounds) do
    do_revision_rounds(%{
      personas: personas,
      topic: topic,
      context: context,
      llm: llm,
      max_rounds: max_rounds,
      round_number: 1,
      previous_positions: positions,
      rounds: [],
      meta: empty_meta()
    })
  end

  defp do_revision_rounds(%{round_number: round_number, max_rounds: max_rounds} = state)
       when round_number > max_rounds do
    {:ok,
     %{
       rounds: state.rounds,
       final_positions: state.previous_positions,
       consensus: last_consensus(state.rounds),
       stop_reason: :max_rounds
     }, state.meta}
  end

  defp do_revision_rounds(state) do
    notify_panel(state.context, :round_started, %{round: state.round_number})

    with {:ok, revisions, revision_meta} <-
           critiques_and_revisions(
             state.personas,
             state.topic,
             state.previous_positions,
             state.rounds,
             state.round_number,
             state.context,
             state.llm
           ),
         {:ok, consensus, consensus_meta} <-
           check_consensus(
             state.topic,
             revisions,
             state.round_number,
             state.context,
             state.llm
           ) do
      round = %{round: state.round_number, positions: revisions, consensus: consensus}
      rounds = state.rounds ++ [round]
      meta = state.meta |> merge_meta(revision_meta) |> merge_meta(consensus_meta)

      cond do
        consensus_reached?(consensus, state.personas, state.context) ->
          {:ok,
           %{
             rounds: rounds,
             final_positions: revisions,
             consensus: consensus,
             stop_reason: :consensus
           }, meta}

        stagnant?(state.previous_positions, revisions) ->
          {:ok,
           %{
             rounds: rounds,
             final_positions: revisions,
             consensus: consensus,
             stop_reason: :stagnation
           }, meta}

        true ->
          do_revision_rounds(%{
            state
            | round_number: state.round_number + 1,
              previous_positions: revisions,
              rounds: rounds,
              meta: meta
          })
      end
    end
  end

  defp critiques_and_revisions(
         personas,
         topic,
         previous_positions,
         previous_rounds,
         round_number,
         context,
         llm
       ) do
    round_brief =
      if previous_rounds == [] do
        render_round("Initial positions", previous_positions)
      else
        render_round("Previous revised positions", previous_positions)
      end

    call_personas(personas, context, llm, :revision, round_number, fn persona ->
      """
      You are continuing an expert panel debate.

      Topic:
      #{topic}

      Persona:
      #{persona.discipline} (#{persona.name})

      Persona instructions:
      #{persona.instructions}

      #{round_brief}

      Debate revision round #{round_number} task:
      Critique the other panelists, then revise your own position. Return Markdown with these sections:
      - Strongest agreement
      - Strongest disagreement
      - Blind spots in other positions
      - Revised conclusion from your discipline
      - Consensus stance: say whether you can accept the emerging panel conclusion, and what must change if not

      Be concrete. Do not merely restate your first answer.
      """
    end)
  end

  defp check_consensus(topic, revisions, round_number, context, llm) do
    notify_panel(context, :consensus_check_started, %{round: round_number})

    prompt = """
    You are the moderator of a structured expert panel.

    Topic:
    #{topic}

    #{render_round("Revised positions after debate round #{round_number}", revisions)}

    Consensus check task:
    Determine whether the panel has reached enough agreement to stop.

    Return exactly this format:
    CONSENSUS: yes or no
    AGREEMENT_COUNT: integer number of panelists who can accept the emerging conclusion
    REASON: one concise sentence
    """

    case call_llm(llm, prompt, context) do
      {:ok, text, meta} ->
        consensus = parse_consensus(text)
        notify_panel(context, :consensus_checked, %{round: round_number, consensus: consensus})
        {:ok, consensus, meta}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp synthesize_conclusion(topic, positions, debate_state, context, llm) do
    notify_panel(context, :synthesis_started, %{stop_reason: debate_state.stop_reason})

    prompt = """
    You are the moderator of a structured expert panel.

    Topic:
    #{topic}

    #{render_round("Initial positions", positions)}

    #{render_revision_rounds(debate_state.rounds)}

    Stop reason:
    #{debate_state.stop_reason}

    Latest consensus check:
    #{render_consensus(debate_state.consensus)}

    Final task:
    Produce the final conclusion reached by the panel in Markdown with these sections:
    - Bottom line
    - Points of consensus
    - Remaining disagreements
    - Practical implications
    - Confidence level and why
    - What evidence would change the conclusion

    If consensus was not reached, state that clearly and preserve the remaining disagreements.
    The conclusion must be balanced, not a simple average. Resolve tensions explicitly.
    """

    case call_llm(llm, prompt, context) do
      {:ok, text, meta} -> {:ok, text, meta}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_consensus(text) do
    normalized = String.downcase(to_string(text))

    consensus? =
      Regex.match?(~r/consensus:\s*yes/, normalized) or
        Regex.match?(~r/합의[:\s]*(yes|예|됨|도달)/, normalized)

    agreement_count =
      case Regex.run(~r/agreement_count:\s*(\d+)/i, to_string(text)) do
        [_, value] -> String.to_integer(value)
        _ -> if(consensus?, do: :all, else: 0)
      end

    %{
      reached?: consensus?,
      agreement_count: agreement_count,
      text: to_string(text)
    }
  end

  defp consensus_reached?(%{reached?: true, agreement_count: :all}, _personas, _context), do: true

  defp consensus_reached?(%{reached?: true, agreement_count: count}, personas, context) do
    count >= required_agreement_count(personas, context)
  end

  defp consensus_reached?(_consensus, _personas, _context), do: false

  defp required_agreement_count(personas, context) do
    threshold =
      context
      |> Map.get(:panel_consensus_threshold, @default_consensus_threshold)
      |> normalize_threshold()

    Float.ceil(length(personas) * threshold)
    |> trunc()
    |> max(1)
  end

  defp normalize_threshold(value) when is_float(value), do: min(max(value, 0.0), 1.0)

  defp normalize_threshold(value) when is_integer(value) and value <= 1,
    do: (value * 1.0) |> normalize_threshold()

  defp normalize_threshold(value) when is_integer(value),
    do: (value / 100) |> normalize_threshold()

  defp normalize_threshold(_value), do: @default_consensus_threshold

  defp stagnant?(previous_positions, revisions) do
    position_fingerprint(previous_positions) == position_fingerprint(revisions)
  end

  defp position_fingerprint(positions) do
    positions
    |> Enum.map_join("\n", fn entry -> normalize_text(entry.text) end)
    |> String.slice(0, 4_000)
  end

  defp normalize_text(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp last_consensus([]), do: nil
  defp last_consensus(rounds), do: rounds |> List.last() |> Map.get(:consensus)

  defp panel_max_rounds(context) do
    context
    |> Map.get(:panel_max_rounds, @default_max_rounds)
    |> normalize_max_rounds()
  end

  defp normalize_max_rounds(value) when is_integer(value), do: max(value, 1)

  defp normalize_max_rounds(value) when is_binary(value) do
    case Integer.parse(value) do
      {rounds, ""} -> normalize_max_rounds(rounds)
      _ -> @default_max_rounds
    end
  end

  defp normalize_max_rounds(_value), do: @default_max_rounds

  defp call_personas(personas, context, llm, phase, round, prompt_builder) do
    Enum.reduce_while(personas, {:ok, [], empty_meta()}, fn persona, {:ok, acc, acc_meta} ->
      notify_panel(context, :persona_started, %{
        phase: phase,
        round: round,
        persona: persona.name,
        discipline: persona.discipline
      })

      case call_llm(llm, prompt_builder.(persona), context) do
        {:ok, text, meta} ->
          entry = %{
            persona: persona.name,
            discipline: persona.discipline,
            text: text
          }

          notify_panel(context, :persona_completed, %{
            phase: phase,
            round: round,
            persona: persona.name,
            discipline: persona.discipline,
            text: text
          })

          {:cont, {:ok, acc ++ [entry], merge_meta(acc_meta, meta)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp call_llm(llm, prompt, context) do
    opts = [
      use_tools: false,
      history: Map.get(context, :history, []),
      notify: Map.get(context, :notify),
      execution_id: Map.get(context, :execution_id),
      session_id: Map.get(context, :session_id)
    ]

    case llm.(prompt, opts) do
      {:ok, %{text: text} = meta} -> {:ok, text, meta}
      {:ok, %{"text" => text} = meta} -> {:ok, text, meta}
      {:error, reason} -> {:error, reason}
    end
  end

  defp panel_personas(context) do
    cond do
      is_list(Map.get(context, :panel_personas)) and Map.get(context, :panel_personas) != [] ->
        context
        |> Map.get(:panel_personas)
        |> Enum.map(&normalize_persona/1)

      selected = selected_persona_skills(context) ->
        Enum.map(selected, &skill_to_persona/1)

      true ->
        @default_personas
    end
  end

  defp selected_persona_skills(context) do
    skills =
      context
      |> Map.get(:selected_skills, [])
      |> Enum.filter(fn skill ->
        tags = Map.get(skill, :tags, []) || []
        capabilities = Map.get(skill, :capabilities, []) || []

        Enum.any?(
          tags ++ capabilities,
          &(String.downcase(to_string(&1)) in ["persona", "debate"])
        )
      end)

    if skills == [], do: nil, else: skills
  end

  defp normalize_persona(persona) when is_map(persona) do
    name = Map.get(persona, :name) || Map.get(persona, "name") || "panelist"
    discipline = Map.get(persona, :discipline) || Map.get(persona, "discipline") || name
    instructions = Map.get(persona, :instructions) || Map.get(persona, "instructions") || ""

    %{
      name: to_string(name),
      discipline: to_string(discipline),
      instructions: to_string(instructions)
    }
  end

  defp normalize_persona(name) do
    %{name: to_string(name), discipline: to_string(name), instructions: ""}
  end

  defp skill_to_persona(skill) do
    %{
      name: Map.get(skill, :name),
      discipline: Map.get(skill, :description, Map.get(skill, :name)),
      instructions: Map.get(skill, :instructions, "")
    }
  end

  defp render_round(title, entries) do
    body =
      Enum.map_join(entries, "\n\n", fn entry ->
        """
        ## #{entry.discipline} (#{entry.persona})
        #{entry.text}
        """
      end)

    """
    #{title}:
    #{body}
    """
  end

  defp render_revision_rounds(rounds) do
    Enum.map_join(rounds, "\n\n", fn round ->
      """
      Debate revision round #{round.round}:
      #{render_round("Positions", round.positions)}

      Consensus:
      #{render_consensus(round.consensus)}
      """
    end)
  end

  defp render_consensus(nil), do: "No consensus check was completed."
  defp render_consensus(%{text: text}), do: text

  defp notify_panel(context, event, payload) do
    case Map.get(context, :notify) do
      pid when is_pid(pid) -> send(pid, {:panel_debate_event, Map.put(payload, :event, event)})
      _ -> :ok
    end
  end

  defp accumulate_meta(context, meta) do
    usage = normalize_usage(meta["usage"] || meta[:usage])
    cost = meta["cost_usd"] || meta[:cost_usd] || 0.0
    usage_history = Map.get(context, :llm_usage, [])

    context
    |> Map.update(:cost_usd, cost, &Float.round(&1 + cost, 6))
    |> Map.put(:estimated_cost, Map.get(context, :cost_usd, 0.0) + cost)
    |> Map.put(:last_llm_usage, usage)
    |> Map.put(:llm_usage, usage_history ++ [usage])
  end

  defp empty_meta, do: %{"usage" => normalize_usage(nil), "cost_usd" => 0.0}

  defp merge_meta(left, right) do
    left_usage = normalize_usage(left["usage"] || left[:usage])
    right_usage = normalize_usage(right["usage"] || right[:usage])

    %{
      "usage" => %{
        prompt_tokens: left_usage.prompt_tokens + right_usage.prompt_tokens,
        completion_tokens: left_usage.completion_tokens + right_usage.completion_tokens,
        total_tokens: left_usage.total_tokens + right_usage.total_tokens
      },
      "cost_usd" =>
        Float.round(
          (left["cost_usd"] || left[:cost_usd] || 0.0) +
            (right["cost_usd"] || right[:cost_usd] || 0.0),
          6
        )
    }
  end

  defp normalize_usage(nil), do: %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
  defp normalize_usage(usage), do: AOS.AgentOS.LLM.Usage.normalize_usage(usage)
end
