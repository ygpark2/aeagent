defmodule AOS.AgentOS.OperationsTest do
  use AOS.DataCase, async: true

  alias AOS.AgentOS.Executions
  alias AOS.AgentOS.Operations

  test "doctor returns operational checks" do
    doctor = Operations.doctor()
    assert doctor.status in ["ok", "degraded"]
    assert is_map(doctor.checks)
    assert Map.has_key?(doctor.checks, :database)
  end

  test "metrics summary includes execution counts" do
    {:ok, _execution} = Executions.enqueue("metrics task", start_immediately: false)

    metrics = Operations.metrics_summary()
    assert metrics.executions_total >= 1
    assert is_map(metrics.executions_by_status)
  end
end
