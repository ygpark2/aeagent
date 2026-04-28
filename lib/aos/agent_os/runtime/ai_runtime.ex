defmodule AOS.AgentOS.Runtime.AIRuntime do
  @moduledoc """
  Manages local AI model loading and inference using Bumblebee and Nx.
  Uses FLAME to scale model workloads.
  """
  use GenServer
  require Logger
  alias AOS.AgentOS.Config
  alias AOS.AgentOS.Runtime.AIPool

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def predict(prompt, _opts \\ []) do
    runtime_type = Config.runtime_type()

    case runtime_type do
      :local ->
        # Use FLAME to run the inference on a specialized worker if needed.
        # The worker node will start this GenServer and load the model.
        FLAME.call(AIPool, fn ->
          GenServer.call(__MODULE__, {:predict, prompt}, 120_000)
        end)

      _ ->
        {:error, "Local runtime not enabled"}
    end
  end

  @impl true
  def init(_opts) do
    # Only load the model if we are in a FLAME worker or if explicitly told to.
    # This prevents the web node from consuming too much memory.
    if FLAME.Parent.get() do
      model_name = Config.agent_local_model()
      Logger.info("[AIRuntime] Loading model on FLAME worker: #{model_name}")

      # Using a small model for default if not specified to avoid OOM
      # In reality, this would be Gemma, Llama, etc.
      {:ok, spec} = Bumblebee.load_spec({:hf, model_name})
      {:ok, model} = Bumblebee.load_model(spec)
      {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_name})
      {:ok, generation_config} = Bumblebee.load_generation_config({:hf, model_name})

      serving =
        Bumblebee.Text.generation(model, tokenizer, generation_config,
          compile: [batch_size: 1, sequence_length: 512],
          defn_options: [compiler: EXLA]
        )

      {:ok, %{serving: serving}}
    else
      {:ok, %{serving: nil}}
    end
  end

  @impl true
  def handle_call({:predict, prompt}, _from, %{serving: serving} = state) do
    if serving do
      output = Nx.Serving.run(serving, prompt)
      result = List.first(output.results).text
      {:reply, result, state}
    else
      {:reply, {:error, "Model not loaded on this node"}, state}
    end
  end
end
