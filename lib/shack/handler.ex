defmodule Shack.Handler do
  @moduledoc false

  require Logger
  use Tortoise.Handler

  def init(args) do
    {:ok, args}
  end

  def connection(_status, state) do
    {:ok, state}
  end

  def handle_message(["shack" | subtopics], payload, state) do
    #Logger.info "mqtt(shack, #{inspect subtopics}, #{payload})"
    handle_shack_message(subtopics, payload, state)
    {:ok, state}
  end
  def handle_message(topics, payload, state) do  # ignore unmatched topics
    Logger.info "unknown mqtt(#{inspect topics}, #{payload})"
    {:ok, state}
  end

  # these mqtt messages are all for the "shack"

  def handle_shack_message(["controller" | subtopics], payload, state) do
    send(Shack.Controller, {:mqtt, subtopics, payload})
    {:ok, state}
  end
  def handle_shack_message(["ic7610" | subtopics], payload, state) do
    send(Icom.IC7610, {:mqtt, subtopics, payload})
    {:ok, state}
  end

  def subscription(_status, _topic_filter, state) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end
end