%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% Handler for accepted connections
%%% @end
%%%
%%% The MIT License (MIT)
%%%
%%% Copyright (c) 2014 Alexander Morozov
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in all
%%% copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%%% SOFTWARE.
%%%-------------------------------------------------------------------

-module(esmpp34_acceptor).
-author("Alexander Morozov aka ~ArchimeD~").


-include("esmpp34.hrl").
-include("esmpp34_defs.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_types.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_constants.hrl").

-behaviour(gen_fsm).

%% API
-export([
         start_link/3
        ]).

%% gen_fsm callbacks
-export([
         init/1,
         open/2,
         bound_trx/2,
         bound_trx/3,
         state_name/3,
         handle_event/3,
         handle_sync_event/4,
         handle_info/3,
         terminate/3,
         code_change/4
        ]).

-define(SERVER, ?MODULE).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @end
%%--------------------------------------------------------------------

-spec(start_link(Id :: non_neg_integer(), Connection :: #smpp_entity{}, Socket :: gen_tcp:socket()) ->
             {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).

start_link(Id, Connection, Socket) ->
    gen_fsm:start_link(?MODULE, [{id, Id}, {connection, Connection}, {socket, Socket}], []).



%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @end
%%--------------------------------------------------------------------

-spec(init(Args :: term()) ->
             {ok, StateName :: atom(), StateData :: #state{}} |
             {ok, StateName :: atom(), StateData :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term()} | ignore).

init(Args) ->
    Id = proplists:get_value(id, Args),
    Connection = proplists:get_value(connection, Args),
    Socket = proplists:get_value(socket, Args),
    io:format("Acceptor started with parameters: ~p~n", [Args]),
    inet:setopts(Socket, [{active, once}]),
    {ok, open, #state{id = Id, connection = Connection, socket = Socket}, 1000}. %% FIXME: make 1000 as timeout macros or record field



%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @end
%%--------------------------------------------------------------------


open(timeout, #state{socket = Socket} = State) ->
    io:format("session init timeout~n"),
    %% FIXME: correct stop
    gen_tcp:close(Socket),
    {stop, normal, State};

open({data, [Head | _], []}, #state{socket = Socket} = State) ->
    inet:setopts(Socket, [{active, once}]),
    proceed_open(State, Head).





bound_trx(enquire_link, #state{socket = Socket, seq = Seq, response_timers = Timers} = State) ->
    NewState = esmpp34_utils:start_el_timer(State),
    Req = #enquire_link{},
    Code = ?ESME_ROK,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Req, Code, Seq)),
    Timer = erlang:send_after(30000, self(), {timeout, Seq, enquire_link}), %% TODO: interval from config
    NewTimers = dict:store(Seq, Timer, Timers),
    {next_state, bound_trx, NewState#state{response_timers = NewTimers, seq = Seq + 1}};

bound_trx({data, Pdus, _}, #state{} = State) ->
    NewState = lists:foldl(fun(Value, Acc) -> esmpp34_utils:receive_data(trx, Acc, Value) end, esmpp34_utils:start_el_timer(State), Pdus),
    %% TODO: handle packets to change state
    {next_state, bound_trx, NewState}.
    


%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_event/[2,3], the instance of this function with
%% the same name as the current state name StateName is called to
%% handle the event.
%%
%% @end
%%--------------------------------------------------------------------


bound_trx({send, Pdu}, _From, #state{seq = Seq} = State) ->
    case esmpp34_utils:send_data(trx, State#state{seq = Seq + 1}, Pdu, Seq) of
        {ok, NewState} ->
            {reply, ok, bound_trx, NewState};
        {error, _} = E ->
            {reply, E, bound_trx, State}
    end;

bound_trx({send, Pdu, Sequence}, _From, #state{} = State) ->
    case esmpp34_utils:send_data(trx, State, Pdu, Sequence) of
        {ok, NewState} ->
            {reply, ok, bound_trx, NewState};
        {error, _} = E ->
            {reply, E, bound_trx, State}
    end;

bound_trx({send, Pdu, Sequence, Status}, _From, #state{} = State) ->
    case esmpp34_utils:send_data(trx, State, Pdu, Sequence, Status) of
        {ok, NewState} ->
            {reply, ok, bound_trx, NewState};
        {error, _} = E ->
            {reply, E, bound_trx, State}
    end.



-spec(state_name(Event :: term(), From :: {pid(), term()},
                 State :: #state{}) ->
             {next_state, NextStateName :: atom(), NextState :: #state{}} |
             {next_state, NextStateName :: atom(), NextState :: #state{},
              timeout() | hibernate} |
             {reply, Reply, NextStateName :: atom(), NextState :: #state{}} |
             {reply, Reply, NextStateName :: atom(), NextState :: #state{},
              timeout() | hibernate} |
             {stop, Reason :: normal | term(), NewState :: #state{}} |
             {stop, Reason :: normal | term(), Reply :: term(),
              NewState :: #state{}}).

state_name(_Event, _From, State) ->
    Reply = ok,
    {reply, Reply, state_name, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @end
%%--------------------------------------------------------------------

-spec(handle_event(Event :: term(), StateName :: atom(),
                   StateData :: #state{}) ->
             {next_state, NextStateName :: atom(), NewStateData :: #state{}} |
             {next_state, NextStateName :: atom(), NewStateData :: #state{},
              timeout() | hibernate} |
             {stop, Reason :: term(), NewStateData :: #state{}}).

handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @end
%%--------------------------------------------------------------------

-spec(handle_sync_event(Event :: term(), From :: {pid(), Tag :: term()},
                        StateName :: atom(), StateData :: term()) ->
             {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: term()} |
             {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: term(),
              timeout() | hibernate} |
             {next_state, NextStateName :: atom(), NewStateData :: term()} |
             {next_state, NextStateName :: atom(), NewStateData :: term(),
              timeout() | hibernate} |
             {stop, Reason :: term(), Reply :: term(), NewStateData :: term()} |
             {stop, Reason :: term(), NewStateData :: term()}).

handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%% @end
%%--------------------------------------------------------------------

-spec(handle_info(Info :: term(), StateName :: atom(),
                  StateData :: term()) ->
             {next_state, NextStateName :: atom(), NewStateData :: term()} |
             {next_state, NextStateName :: atom(), NewStateData :: term(),
              timeout() | hibernate} |
             {stop, Reason :: normal | term(), NewStateData :: term()}).

handle_info({tcp, Socket,  Bin}, StateName, #state{data = OldData} = StateData) ->
    %% io:format("data: ~p~n", [Bin]),
    Data = lists:foldl(fun(Data, Accumulator) ->
                               <<Accumulator/binary, Data/binary>>
                       end, <<OldData/binary, Bin/binary>>, esmpp34_utils:do_recv(Socket, [], 10)),
    {KnownPDU, UnknownPDU, Rest} = esmpp34raw:unpack_sequence(Data),
    Result = ?MODULE:StateName({data, KnownPDU, UnknownPDU}, StateData#state{data = Rest}),
    inet:setopts(Socket, [{active, once}]),
    Result;

handle_info({timeout, Seq, enquire_link}, _, #state{response_timers = Timers} = State) ->
    io:format("Timeout for enquire_link ~p~n", [Seq]),
    NewTimers = esmpp34_utils:cancel_timeout(Seq, Timers),
    {stop, normal, State#state{response_timers = NewTimers}}; %% FIXME: why stop?

handle_info({tcp_closed, _Socket}, _StateName, #state{response_timers = Timers} = State) ->
    io:format("Socket closed, cancelling timers...~n"),
    lists:foreach(fun(Timer) -> erlang:cancel_timer(Timer) end, dict:to_list(Timers)),
    {stop, normal, State#state{response_timers = []}};

handle_info({tcp_error, _Socket}, _StateName, #state{response_timers = Timers} = State) ->
    %% FIXME: maybe do no close
    io:format("Socket closed, cancelling timers...~n"),
    lists:foreach(fun(Timer) -> erlang:cancel_timer(Timer) end, dict:to_list(Timers)),
    {stop, normal, State#state{response_timers = []}};

handle_info({'DOWN', _MonitorRef, process, DownPid, _}, _StateName, #state{dir_pid = {Pid, _Ref}}) when DownPid == Pid ->
    {stop, normal};

handle_info(enquire_link, StateName, #state{} = State) ->
    ?MODULE:StateName(enquire_link, State).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------

-spec(terminate(Reason :: normal | shutdown | {shutdown, term()}
                        | term(), StateName :: atom(), StateData :: term()) -> term()).

terminate(_Reason, _StateName, _State) ->
    ok.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------

-spec(code_change(OldVsn :: term() | {down, term()}, StateName :: atom(),
                  StateData :: #state{}, Extra :: term()) ->
             {ok, NextStateName :: atom(), NewStateData :: #state{}}).

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.



%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Proceed packages in open state.
%% @end
%%--------------------------------------------------------------------

-spec proceed_open(State, Pdu) -> {next_state, StateName, StateData} |
                                  {stop, Status, StateData} when
      State :: #state{},
      Pdu :: #pdu{},
      StateName :: bound_trx | bound_tx | bound_rx | open,
      StateData :: #state{},
      Status :: normal.


proceed_open(#state{connection = #smpp_entity{id = ConnectionId} = _Connection, socket = Socket} = State,
             #pdu{sequence_number = Seq, body = #bind_transceiver{password = Password, system_id = SystemId} = Packet}) ->
    io:format("===> TRANSCEIVER: ~p~n", [Packet]),
    Result = esmpp34_manager:register_connection(ConnectionId, trx, SystemId, Password),
    io:format("result of login: ~p~n", [Result]),
    %%     {next_state, open, State};
    case Result of
        {ok, DirPid} ->
            Resp = #bind_transceiver_resp{system_id = "TEST", sc_interface_version = 16#34},
            Code = ?ESME_ROK,
            gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
            Ref = erlang:monitor(process, DirPid),
	    NewState = esmpp34_utils:start_el_timer(State),
            {next_state, bound_trx, NewState#state{dir_pid = {DirPid, Ref}}};
        {error, Reason} ->
            Resp = #bind_transceiver_resp{system_id = "TEST", sc_interface_version = 16#34},
            Code = esmpp34_utils:reason2code(Reason),
            gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
            {stop, normal, State} %% FIXME: do something
    end;

proceed_open(#state{connection = #smpp_entity{} = _Connection, socket = _Socket} = State,
             #pdu{sequence_number = _Seq, body = #bind_transmitter{} = Packet}) ->
    io:format("===> TRANSMITTER: ~p~n", [Packet]),
    {next_state, open, State};

proceed_open(#state{connection = #smpp_entity{} = _Connection, socket = _Socket} = State,
             #pdu{sequence_number = _Seq, body = #bind_receiver{} = Packet}) ->
    io:format("===> RECEIVER: ~p~n", [Packet]),
    {next_state, open, State};

proceed_open(#state{} = State, A) ->
    io:format("error received unknown packet ~p~n", [A]),
    {next_state, open, State}.

