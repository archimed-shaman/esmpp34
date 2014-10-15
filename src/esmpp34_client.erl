%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% Client connection handler
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

-module(esmpp34_client).
-author("Alexander Morozov aka ~ArchimeD~").

-behaviour(gen_fsm).

-include("esmpp34.hrl").
-include("esmpp34_defs.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_types.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_constants.hrl").

%% API
-export([start_link/4]).

%% gen_fsm callbacks
-export([
         init/1,
         open/2,
         open_bind_resp/2,
         bound_trx/2,
         bound_tx/2,
         bound_rx/2,
         bound_trx/3,
         bound_tx/3,
         bound_rx/3,
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
%% @end
%%--------------------------------------------------------------------

start_link(Host, Port, Entity, Mode) ->
    gen_fsm:start_link(?MODULE, [{host, Host}, {port, Port}, {connection, Entity}, {mode, Mode}], []).



%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%% @end
%%--------------------------------------------------------------------

-spec(init(Args :: term()) ->
             {ok, StateName :: atom(), StateData :: #state{}} |
             {ok, StateName :: atom(), StateData :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term()} | ignore).


init(Args) ->
    Connection = proplists:get_value(connection, Args),
    Host = proplists:get_value(host, Args),
    Port = proplists:get_value(port, Args),
    Mode = proplists:get_value(mode, Args),
    Id = Connection#smpp_entity.id,
    erlang:send_after(1, self(), connect),
    {ok, open, #state{id = Id, connection = Connection, mode = Mode, host = Host, port = Port}}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle open state.
%% @end
%%--------------------------------------------------------------------

-spec open(Event, State) -> {next_state, NextStateName, NextState} |
                            {next_state, NextStateName, NextState, timeout() | hibernate} |
                            {stop, Reason, NewState} when
      Event :: term(),
      State :: #state{},
      NextStateName :: atom(),
      NextState :: #state{},
      NewState :: #state{},
      Reason :: term().


open(connect, #state{ mode = Mode,
                      host = Host,
                      port = Port} = State) when Mode == trx ->
    starter(Host, Port, State);

open(bind, #state{ socket = Socket,
                   mode = Mode,
                   connection = #smpp_entity{system_id = SystemId, password = Password},
                   seq = Seq } = State) when Mode == tx ->
    Req = #bind_transmitter{system_id = SystemId,
                            password = Password,
                            system_type = [], %% FIXME: maybe, its necessary to set correct system type
                            interface_version = 16#34
                            %% TODO: fill this fields
                            %% addr_ton           = 0,
                            %% addr_npi           = 0,
                            %% address_range      = []
                           },
    gen_tcp:send(Socket, esmpp34raw:pack_single(Req, ?ESME_ROK, Seq)),
    {next_state, open_bind_resp, State#state{seq = Seq + 1}, 10000}; %% TODO: timeout from config

open(bind, #state{ socket = Socket,
                   mode = Mode,
                   connection = #smpp_entity{system_id = SystemId, password = Password},
                   seq = Seq } = State) when Mode == rx ->
    Req = #bind_receiver{system_id = SystemId,
                         password = Password,
                         system_type = [], %% FIXME: maybe, its necessary to set correct system type
                         interface_version = 16#34
                         %% TODO: fill this fields
                         %% addr_ton           = 0,
                         %% addr_npi           = 0,
                         %% address_range      = []
                        },
    gen_tcp:send(Socket, esmpp34raw:pack_single(Req, ?ESME_ROK, Seq)),
    {next_state, open_bind_resp, State#state{seq = Seq + 1}, 10000}; %% TODO: timeout from config

open({data, Pdus, UnknownPdus}, #state{socket = Socket} = State) ->
    lists:foreach(fun(#pdu{sequence_number = Seq}) ->
                          esmpp34_utils:reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS)
                  end, Pdus ++ UnknownPdus),
    {next_state, open, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle open_bind_resp state.
%% @end
%%--------------------------------------------------------------------

-spec open_bind_resp(Event, State) -> {next_state, NextStateName, NextState} |
                            {next_state, NextStateName, NextState, timeout() | hibernate} |
                            {stop, Reason, NewState} when
      Event :: term(),
      State :: #state{},
      NextStateName :: atom(),
      NextState :: #state{},
      NewState :: #state{},
      Reason :: term().


open_bind_resp({data, [], UnknownPdus}, #state{socket = Socket} = State) ->
    lists:foreach(fun(#pdu{sequence_number = Seq}) ->
                          esmpp34_utils:reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS)
                  end, UnknownPdus),
    %% FIXME: potential bug. If other side sends data continiously without bind_resp,
    %% timeout will newer appear. Maybe, add stand-alone timer.
    {next_state, open_bind_resp, State, 10000};

open_bind_resp({data, [#pdu{} = Resp | KnownPDUs], UnknownPDUs}, #state{ connection = #smpp_entity{id = Id},
                                                                         socket = Socket,
                                                                         mode = Mode } = State) ->
    case proceed_bind_resp(Resp, Mode) of
        {ok, NextState} ->
            case esmpp34_manager:register_connection(Id, Mode) of
                {ok, DirPid} ->
                    io:format("Connected!~n"),
                    Ref = erlang:monitor(process, DirPid),
                    NewState = esmpp34_utils:start_el_timer(State),
                    ?MODULE:NextState({data, KnownPDUs, UnknownPDUs}, NewState#state{dir_pid = {DirPid, Ref}});
                {error, _Reason} ->
                    {stop, normal, State}
            end;
        {error, Error} ->
            io:format("Unable to connect: ~p~n", [Error]),
            {stop, {error, unable_connect}, State};
        {unknown_command, Seq, CommandId, _Status} ->
            io:format("Received unknown PDU in unbinded: ~p~n", [CommandId]),
            esmpp34_utils:reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
            open_bind_resp({date, KnownPDUs, UnknownPDUs}, State)
    end;

open_bind_resp(timeout, #state{socket = Socket} = State) ->
    io:format("session init timeout~n"),
    gen_tcp:close(Socket),
    {stop, {error, bind_timeout}, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle bound_trx state.
%% @end
%%--------------------------------------------------------------------

-spec bound_trx(Event, State) -> {next_state, NextStateName, NextState} |
                                 {next_state, NextStateName, NextState, timeout() | hibernate} |
                                 {stop, Reason, NewState} when
      Event :: term(),
      State :: #state{},
      NextStateName :: atom(),
      NextState :: #state{},
      NewState :: #state{},
      Reason :: term().


bound_trx(enquire_link, #state{} = State) ->
    {next_state, bound_trx, esmpp34_utils:send_enquire_link(State)};

bound_trx({data, Pdus, _}, #state{} = State) ->
    NewState = lists:foldl(fun(Value, Acc) -> esmpp34_utils:receive_data(trx, Acc, Value) end, esmpp34_utils:start_el_timer(State), Pdus),
    %% TODO: handle packets to change state
    {next_state, bound_trx, NewState};

bound_trx({timeout, Seq}, #state{} = State) ->
    io:format("Timeout for sequence ~p~n", [Seq]),
    NewState = esmpp34_utils:receive_timeout(Seq, State),
    {next_state, bound_trx, NewState}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle bound_trx state.
%% @end
%%--------------------------------------------------------------------

-spec bound_trx(Event, From, State) -> {next_state, NextStateName, NextState} |
                                       {next_state, NextStateName, NextState, timeout() | hibernate} |
                                       {reply, Reply, NextStateName, NextState} |
                                       {reply, Reply, NextStateName, NextState, timeout() | hibernate} |
                                       {stop, Reason, NewState} |
                                       {stop, Reason, Reply, NewState} when
      Event :: term(),
      From :: {pid(), term()},
      State :: #state{},
      NextStateName :: atom(),
      NextState :: #state{},
      NewState :: #state{},
      Reply :: term().


bound_trx({send, Pdu, From}, _, #state{seq = Seq} = State) ->
    case esmpp34_utils:send_data(trx, State#state{seq = Seq + 1}, Pdu, From, Seq) of
        {ok, NewState} ->
            {reply, ok, bound_trx, NewState};
        {error, _} = E ->
            {reply, E, bound_trx, State}
    end;

bound_trx({send, Pdu, From, Sequence}, _, #state{} = State) ->
    case esmpp34_utils:send_data(trx, State, Pdu, From, Sequence) of
        {ok, NewState} ->
            {reply, ok, bound_trx, NewState};
        {error, _} = E ->
            {reply, E, bound_trx, State}
    end;

bound_trx({send, Pdu, From, Sequence, Status}, _, #state{} = State) ->
    case esmpp34_utils:send_data(trx, State, Pdu, From, Sequence, Status) of
        {ok, NewState} ->
            {reply, ok, bound_trx, NewState};
        {error, _} = E ->
            {reply, E, bound_trx, State}
    end.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle bound_tx state.
%% @end
%%--------------------------------------------------------------------

-spec bound_tx(Event, State) -> {next_state, NextStateName, NextState} |
                                {next_state, NextStateName, NextState, timeout() | hibernate} |
                                {stop, Reason, NewState} when
      Event :: term(),
      State :: #state{},
      NextStateName :: atom(),
      NextState :: #state{},
      NewState :: #state{},
      Reason :: term().


bound_tx(enquire_link, #state{} = State) ->
    {next_state, bound_tx, esmpp34_utils:send_enquire_link(State)};

bound_tx({data, Pdus, _}, #state{} = State) ->
    NewState = lists:foldl(fun(Value, Acc) -> esmpp34_utils:receive_data(tx, Acc, Value) end, esmpp34_utils:start_el_timer(State), Pdus),
    %% TODO: handle packets to change state
    {next_state, bound_tx, NewState};

bound_tx({timeout, Seq}, #state{} = State) ->
    io:format("Timeout for sequence ~p~n", [Seq]),
    NewState = esmpp34_utils:receive_timeout(Seq, State),
    {next_state, bound_tx, NewState}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle bound_tx state.
%% @end
%%--------------------------------------------------------------------

-spec bound_tx(Event, From, State) -> {next_state, NextStateName, NextState} |
                                      {next_state, NextStateName, NextState, timeout() | hibernate} |
                                      {reply, Reply, NextStateName, NextState} |
                                      {reply, Reply, NextStateName, NextState, timeout() | hibernate} |
                                      {stop, Reason, NewState} |
                                      {stop, Reason, Reply, NewState} when
      Event :: term(),
      From :: {pid(), term()},
      State :: #state{},
      NextStateName :: atom(),
      NextState :: #state{},
      NewState :: #state{},
      Reply :: term().


bound_tx({send, Pdu, From}, _, #state{seq = Seq} = State) ->
    case esmpp34_utils:send_data(tx, State#state{seq = Seq + 1}, Pdu, From, Seq) of
        {ok, NewState} ->
            {reply, ok, bound_tx, NewState};
        {error, _} = E ->
            {reply, E, bound_tx, State}
    end;

bound_tx({send, Pdu, From, Sequence}, _, #state{} = State) ->
    case esmpp34_utils:send_data(tx, State, Pdu, From, Sequence) of
        {ok, NewState} ->
            {reply, ok, bound_tx, NewState};
        {error, _} = E ->
            {reply, E, bound_tx, State}
    end;

bound_tx({send, Pdu, From, Sequence, Status}, _, #state{} = State) ->
    case esmpp34_utils:send_data(tx, State, Pdu, From, Sequence, Status) of
        {ok, NewState} ->
            {reply, ok, bound_tx, NewState};
        {error, _} = E ->
            {reply, E, bound_tx, State}
    end.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle bound_rx state.
%% @end
%%--------------------------------------------------------------------

-spec bound_rx(Event, State) -> {next_state, NextStateName, NextState} |
                                {next_state, NextStateName, NextState, timeout() | hibernate} |
                                {stop, Reason, NewState} when
      Event :: term(),
      State :: #state{},
      NextStateName :: atom(),
      NextState :: #state{},
      NewState :: #state{},
      Reason :: term().


bound_rx(enquire_link, #state{} = State) ->
    {next_state, bound_tx, esmpp34_utils:send_enquire_link(State)};

bound_rx({data, Pdus, _}, #state{} = State) ->
    NewState = lists:foldl(fun(Value, Acc) -> esmpp34_utils:receive_data(tx, Acc, Value) end, esmpp34_utils:start_el_timer(State), Pdus),
    %% TODO: handle packets to change state
    {next_state, bound_tx, NewState};

bound_rx({timeout, Seq}, #state{} = State) ->
    io:format("Timeout for sequence ~p~n", [Seq]),
    NewState = esmpp34_utils:receive_timeout(Seq, State),
    {next_state, bound_tx, NewState}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle bound_rx state.
%% @end
%%--------------------------------------------------------------------

-spec bound_rx(Event, From, State) -> {next_state, NextStateName, NextState} |
                                      {next_state, NextStateName, NextState, timeout() | hibernate} |
                                      {reply, Reply, NextStateName, NextState} |
                                      {reply, Reply, NextStateName, NextState, timeout() | hibernate} |
                                      {stop, Reason, NewState} |
                                      {stop, Reason, Reply, NewState} when
      Event :: term(),
      From :: {pid(), term()},
      State :: #state{},
      NextStateName :: atom(),
      NextState :: #state{},
      NewState :: #state{},
      Reason :: term(),
      Reply :: term().


bound_rx({send, Pdu, From}, _, #state{seq = Seq} = State) ->
    case esmpp34_utils:send_data(rx, State#state{seq = Seq + 1}, Pdu, From, Seq) of
        {ok, NewState} ->
            {reply, ok, bound_rx, NewState};
        {error, _} = E ->
            {reply, E, bound_rx, State}
    end;

bound_rx({send, Pdu, From, Sequence}, _, #state{} = State) ->
    case esmpp34_utils:send_data(rx, State, Pdu, From, Sequence) of
        {ok, NewState} ->
            {reply, ok, bound_rx, NewState};
        {error, _} = E ->
            {reply, E, bound_rx, State}
    end;

bound_rx({send, Pdu, From, Sequence, Status}, _, #state{} = State) ->
    case esmpp34_utils:send_data(rx, State, Pdu, From, Sequence, Status) of
        {ok, NewState} ->
            {reply, ok, bound_rx, NewState};
        {error, _} = E ->
            {reply, E, bound_rx, State}
    end.



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


%% 'bind' is sent in starter
handle_info(connect, StateName, #state{} = StateData) ->
    ?MODULE:StateName(connect, StateData);

handle_info({tcp, _Socket,  Bin}, StateName, #state{data = OldData} = StateData) ->
    Data = <<OldData/binary, Bin/binary>>,
    {KnownPDU, UnknownPDU, Rest} = esmpp34raw:unpack_sequence(Data),
    Result = ?MODULE:StateName({data, KnownPDU, UnknownPDU}, StateData#state{data = Rest}),
    Result;

handle_info({timeout, Seq, enquire_link}, _, #state{} = State) ->
    io:format("Timeout for enquire_link ~p~n", [Seq]),
    {stop, {error, enquire_link_timeout}, esmpp34_utils:handle_enquire_link_resp(State)};

handle_info({timeout, _Seq} = Msg, StateName, #state{} = State) ->
    ?MODULE:StateName(Msg, State);

handle_info({tcp_closed, _Socket}, _StateName, #state{response_timers = Timers} = State) ->
    io:format("Socket closed, cancelling timers...~n"),
    lists:foreach(fun(Timer) -> erlang:cancel_timer(Timer) end, dict:to_list(Timers)),
    %% TODO: send request to restart connection
    timer:sleep(1000), %% TODO: from config
    {stop, {error, tcp_closed}, State#state{response_timers = []}};

handle_info({'DOWN', _MonitorRef, process, DownPid, _}, _StateName, #state{dir_pid = {Pid, _Ref}} = State) when DownPid == Pid ->
    {stop, normal, State};

handle_info(enquire_link, StateName, #state{} = State) ->
    ?MODULE:StateName(enquire_link, State).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
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
%% Initialize gen_server state, connect to host, etc.
%% @end
%%--------------------------------------------------------------------

-spec starter(Host, Port, State) -> {ok, StateName, NewState} |
                                    {stop, Reason} when
      Host :: string(),
      Port :: inet:port_number(),
      State :: #state{},
      StateName :: open,
      NewState :: #state{},
      Reason :: term().


starter(Host, Port, #state{connection = #smpp_entity{system_id = SystemId, password = Password},
                           seq = Seq} = State) ->
    case esmpp34_utils:resolver(Host) of
        {ok, IpAddress} ->
            Options = [binary, {packet, raw}, {active, true}, {reuseaddr, true}],
            io:format("Connecting to ~p(~p):~p~n", [Host, IpAddress, Port]),
            case gen_tcp:connect(IpAddress, Port, Options, 30000) of %% TODO: timeout from config?
                {ok, Socket} ->
                    io:format("Connected to ~p:~p~n", [Host,Port]),
                    Req = #bind_transceiver{system_id = SystemId,
                                            password = Password,
                                            system_type = [], %% FIXME: maybe, its necessary to set correct system type
                                            interface_version = 16#34
                                            %% TODO: fill this fields
                                            %% addr_ton           = 0,
                                            %% addr_npi           = 0,
                                            %% address_range      = []
                                           },
                    gen_tcp:send(Socket, esmpp34raw:pack_single(Req, ?ESME_ROK, Seq)),
                    {next_state, open_bind_resp, State#state{socket = Socket, seq = Seq + 1}, 10000}; %% TODO: timeout from config
                {error, Reason} ->
                    timer:sleep(1000), %% TODO: from config
                    io:format("TCP connect error start: ~p~n", [Reason]),
                    {stop, {error, Reason}, State}
            end;
        Error ->
            io:format("Unable parse IP ~p : [~p], stopping client... ~n", [Host, Error]),
            {stop, normal, State}
    end.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Proceed response for bind command with success or negative code
%% @end
%%--------------------------------------------------------------------

-spec proceed_bind_resp(Pdu, Mode) -> {ok, StateName} |
                                      {error, Status} |
                                      {unknown_command, SequenceNumber, CommandId, Status} when
      Pdu :: #pdu{},
      Mode :: trx | tx | rx,
      StateName :: bound_trx | bound_tx | bound_rx,
      Status :: non_neg_integer(),
      SequenceNumber :: non_neg_integer(),
      CommandId :: non_neg_integer().


proceed_bind_resp(#pdu{command_id = ?bind_transceiver_resp, command_status = Status}, Mode) when Mode == trx, Status == ?ESME_ROK ->
    {ok, bound_trx};

proceed_bind_resp(#pdu{command_id = ?bind_transmitter_resp, command_status = Status}, Mode) when Mode == tx, Status == ?ESME_ROK ->
    {ok, bound_tx};

proceed_bind_resp(#pdu{command_id = ?bind_receiver_resp, command_status = Status}, Mode) when Mode == rx, Status == ?ESME_ROK ->
    {ok, bound_rx};

proceed_bind_resp(#pdu{command_id = ?bind_transceiver_resp, command_status = Status}, _Mode) when Status /= ?ESME_ROK ->
    {error, Status};

proceed_bind_resp(#pdu{sequence_number = Num, command_id = CommandId, command_status = Status}, _Mode)  ->
    {unknown_command, Num, CommandId, Status}.
