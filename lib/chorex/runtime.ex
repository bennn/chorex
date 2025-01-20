defmodule Chorex.Runtime do
  alias Chorex.RuntimeState
  import Chorex.RuntimeState

  defguard correct_session(m, s) when elem(m, 0) == s.session_tok

  #
  # ----- Helper functions -----
  #

  # Looks at the stack and emits the proper return tuple
  @spec continue_on_stack(any(), RuntimeState.t()) ::
          {:noreply, RuntimeState.t(), {:continue, any()}}
  def continue_on_stack(ret_val, state) do
    case state.stack do
      [{:recv, _, _, _, _} | _] ->
        {:noreply, state, {:continue, :try_recv}}

      [{:return, _, _} | _] ->
        {:noreply, state, {:continue, {:return, ret_val}}}
    end
  end

  # DO NOT USE; DEMONSTRATION ONLY
  defmacro chorex_send(sender, receiver, civ, message) do
    config = Macro.var(:config, Chorex)
    state = Macro.var(:state, Chorex)

    quote do
      send(
        unquote(config)[unquote(receiver)],
        {:chorex, {unquote(state).session_tok, unquote(civ), unquote(sender), unquote(receiver)},
         unquote(message)}
      )
    end
  end

  #
  # ----- GenServer functions -----
  #

  def init({actor_name, impl_name, return_to, session_tok}) do
    state = %RuntimeState{
      # network configuration
      config: nil,
      # name of this actor
      actor: actor_name,
      # name of implementing module
      impl: impl_name,
      # session token
      session_tok: session_tok,
      # local variables
      vars: %{},
      # waiting messages
      inbox: :queue.new(),
      # call stack
      stack: [{:return, :finish_choreography, %{parent: return_to}}]
    }

    {:ok, state}
  end

  def handle_info({:config, config, init_args}, %RuntimeState{} = state) do
    args = init_args ++ [%{state | config: config}]
    apply(state.actor, :run, args)
  end

  def handle_info({:chorex, civ_tok, msg}, %RuntimeState{} = state)
      when correct_session(civ_tok, state) do
    # dbg({state.actor, :recv, msg})
    {:noreply, push_inbox({civ_tok, msg}, state), {:continue, :try_recv}}
  end

  def handle_info({:choice, civ_tok, selection}, %RuntimeState{} = state)
      when correct_session(civ_tok, state) do
    {:noreply, push_inbox({civ_tok, {:choice, selection}}, state), {:continue, :try_recv}}
  end

  def handle_continue(:try_recv, %RuntimeState{stack: [{:recv, _, _, _, _} | _]} = state) do
    # Run through state.inbox looking for something matching `(car state.stack)`
    [{:recv, civ_tok, match_func, cont_tok, vars} | rst_stack] = state.stack

    # Find the first thing in the queue matching `msg_pat` and drop it
    # the match_func gets generated by Chorex.project_sequence(Alice.(e1) ~> Bob.(e2))
    matcher =
      state.inbox
      |> :queue.to_list()
      |> Enum.find(fn {^civ_tok, _m} -> true
                      _ -> false end)

    # dbg({state.actor, :process_recv, matcher})

    if matcher do
      # match found: drop from queue, continue on the frame with the new message
      matched_vars = match_func.(elem(matcher, 1))
      vars = Map.merge(vars, matched_vars)
      {:noreply, %{drop_inbox(matcher, state) | stack: rst_stack},
       {:continue, {cont_tok, vars, elem(matcher, 1)}}}
    else
      # No match found; keep waiting
      {:noreply, state}
    end
  end

  def handle_continue(:try_recv, %RuntimeState{} = state), do: {:noreply, state}

  def handle_continue({:return, ret_val}, %RuntimeState{} = state) do
    # dbg({state.actor, :return, ret_val})
    [{:return, cont_tok, vars} | rest_stack] = state.stack
    {:noreply, %{state | stack: rest_stack, vars: vars}, {:continue, {cont_tok, ret_val}}}
  end

  def handle_continue({:finish_choreography, ret_val}, %RuntimeState{} = state) do
    send(state.vars.parent, {:chorex_return, state.actor, ret_val})
    {:noreply, state}
  end

  defmacro __using__(_args) do
    quote do
      use GenServer
      alias Chorex.Runtime
      import Chorex.Runtime
      import Chorex.RuntimeState

      @impl true
      defdelegate init(start), to: Runtime

      @impl true
      defdelegate handle_info(msg, state), to: Runtime

      # Need to special-case these ones because they're defined by
      # Runtime. Can't use defdelegate because the impl needs to add
      # its own function clauses.
      @impl true
      def handle_continue(:try_recv, state), do: Runtime.handle_continue(:try_recv, state)
      def handle_continue({:return, _} = m, state), do: Runtime.handle_continue(m, state)
      def handle_continue({:finish_choreography, _} = m, state), do: Runtime.handle_continue(m, state)
    end
  end
end
