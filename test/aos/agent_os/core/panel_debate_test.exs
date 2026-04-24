defmodule AOS.AgentOS.Core.PanelDebateTest do
  use AOS.DataCase, async: true

  alias AOS.AgentOS.Core.Nodes.PanelDebate

  test "runs structured persona debate and stores final conclusion" do
    test_pid = self()

    fake_llm = fn prompt, opts ->
      send(test_pid, {:llm_prompt, prompt, opts})

      text =
        cond do
          String.contains?(prompt, "Final task") ->
            "Final panel conclusion"

          String.contains?(prompt, "Consensus check task") ->
            "CONSENSUS: yes\nAGREEMENT_COUNT: 2\nREASON: aligned"

          String.contains?(prompt, "Debate revision round") ->
            "Critique and revised position"

          true ->
            "Initial position"
        end

      {:ok,
       %{
         "usage" => %{prompt_tokens: 1, completion_tokens: 1, total_tokens: 2},
         "cost_usd" => 0.01,
         text: text
       }}
    end

    context = %{
      task: "Why do cities become unaffordable?",
      panel_llm: fake_llm,
      panel_max_rounds: 1,
      notify: self(),
      panel_personas: [
        %{name: "historian", discipline: "Historian", instructions: "Use historical context."},
        %{name: "economist", discipline: "Economist", instructions: "Use incentives."}
      ]
    }

    assert {:ok, updated_context} = PanelDebate.run(context, [])
    assert updated_context.result == "Final panel conclusion"
    assert updated_context.last_outcome == :success
    assert updated_context.panel_debate.topic == "Why do cities become unaffordable?"
    assert length(updated_context.panel_debate.initial_positions) == 2
    assert length(updated_context.panel_debate.revised_positions) == 2
    assert length(updated_context.panel_debate.revision_rounds) == 1
    assert updated_context.panel_debate.stop_reason == :consensus
    assert length(updated_context.llm_usage) == 3
    assert_in_delta updated_context.cost_usd, 0.06, 0.001

    assert_received {:llm_prompt, initial_prompt, initial_opts}
    assert initial_prompt =~ "Round 1 task"
    assert initial_opts[:use_tools] == false

    assert_received {:panel_debate_event, %{event: :started}}
    assert_received {:panel_debate_event, %{event: :persona_completed, phase: :initial_position}}

    assert_received {:llm_prompt, critique_prompt, _opts}
    assert critique_prompt =~ "Round 1 task"

    assert_received {:llm_prompt, revision_prompt, _opts}
    assert revision_prompt =~ "Debate revision round 1 task"
    assert_received {:panel_debate_event, %{event: :consensus_checked}}
    assert_received {:panel_debate_event, %{event: :synthesis_started}}
  end

  test "repeats revision rounds until consensus or max rounds" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fake_llm = fn prompt, _opts ->
      text =
        cond do
          String.contains?(prompt, "Consensus check task") ->
            count = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

            if count >= 2 do
              "CONSENSUS: yes\nAGREEMENT_COUNT: 2\nREASON: agreement reached"
            else
              "CONSENSUS: no\nAGREEMENT_COUNT: 1\nREASON: still disputed"
            end

          String.contains?(prompt, "Final task") ->
            "Final after repeated debate"

          String.contains?(prompt, "Debate revision round") ->
            "Revised position #{System.unique_integer([:positive])}"

          true ->
            "Initial position #{System.unique_integer([:positive])}"
        end

      {:ok, %{"usage" => %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}, text: text}}
    end

    context = %{
      task: "Should a city cap rents?",
      panel_llm: fake_llm,
      panel_max_rounds: 3,
      panel_personas: [
        %{name: "sociologist", discipline: "Sociologist", instructions: "Use structures."},
        %{name: "economist", discipline: "Economist", instructions: "Use incentives."}
      ]
    }

    assert {:ok, updated_context} = PanelDebate.run(context, [])
    assert updated_context.result == "Final after repeated debate"
    assert updated_context.panel_debate.stop_reason == :consensus
    assert length(updated_context.panel_debate.revision_rounds) == 2
  end

  test "stops at max rounds when consensus is not reached" do
    fake_llm = fn prompt, _opts ->
      text =
        cond do
          String.contains?(prompt, "Consensus check task") ->
            "CONSENSUS: no\nAGREEMENT_COUNT: 1\nREASON: disputed"

          String.contains?(prompt, "Final task") ->
            "Final with remaining disagreements"

          String.contains?(prompt, "Debate revision round") ->
            "Changing position #{System.unique_integer([:positive])}"

          true ->
            "Initial position #{System.unique_integer([:positive])}"
        end

      {:ok, %{"usage" => %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}, text: text}}
    end

    context = %{
      task: "Should a city cap rents?",
      panel_llm: fake_llm,
      panel_max_rounds: 2,
      panel_personas: [
        %{name: "sociologist", discipline: "Sociologist", instructions: "Use structures."},
        %{name: "economist", discipline: "Economist", instructions: "Use incentives."}
      ]
    }

    assert {:ok, updated_context} = PanelDebate.run(context, [])
    assert updated_context.panel_debate.stop_reason == :max_rounds
    assert length(updated_context.panel_debate.revision_rounds) == 2
  end

  test "uses selected persona skills when available" do
    fake_llm = fn _prompt, _opts ->
      {:ok, %{"usage" => %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}, text: "ok"}}
    end

    context = %{
      task: "Analyze a public policy",
      panel_llm: fake_llm,
      selected_skills: [
        %{
          name: "sociologist",
          description: "Sociologist",
          instructions: "Focus on social structures.",
          tags: ["persona"],
          capabilities: ["debate"]
        }
      ]
    }

    assert {:ok, updated_context} = PanelDebate.run(context, [])

    assert [%{name: "sociologist", discipline: "Sociologist"}] =
             updated_context.panel_debate.personas
  end
end
