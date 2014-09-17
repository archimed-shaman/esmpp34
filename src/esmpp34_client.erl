%%%-------------------------------------------------------------------
%%% @author morozov
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 16. Сент. 2014 18:35
%%%-------------------------------------------------------------------
-module(esmpp34_client).
-author("morozov").

-behaviour(gen_fsm).

-include("esmpp34.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_types.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_constants.hrl").

%% API
-export([start_link/4]).

%% gen_fsm callbacks
-export([init/1,
         open/2,
         open_bind_resp/2,
         state_name/3,
         handle_event/3,
         handle_sync_event/4,
         handle_info/3,
         terminate/3,
         code_change/4]).

-define(SERVER, ?MODULE).

-record(state, { response_timers = dict:new(),
                 data = <<>>,
                 socket,
                 host,
                 port,
                 connection,
                 mode,
                 seq = 0 }).

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
%%
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
    io:format("Connecting to ~p:~p~n", [Host,Port]),
    starter(Host, Port, #state{host = Host, port = Port, connection = Connection, mode = Mode}).


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

open(bind, #state{socket = Socket,
                  mode = Mode,
                  connection = #smpp_entity{system_id = SystemId, password = Password},
                  seq = Seq,
                  response_timers = Timers} = State) when Mode == trx ->
    Req = #bind_transceiver{system_id = SystemId,
                            password = Password,
                            system_type = [], %% FIXME: maybe, its necessary to set correct system type
                            interface_version = 16#34
                            %% TODO: fill this fields
                            %% addr_ton           = 0,
                            %% addr_npi           = 0,
                            %% address_range      = []
                           },
    Code = ?ESME_ROK,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Req, Code, Seq)),
    Timer = erlang:send_after(10000, self(), {timeout, Seq}), %% TODO: timeout from config
    Newtimers = dict:store(Seq, Timer, Timers),
    {next_state, open_bind_resp, State#state{seq = Seq + 1, response_timers = Newtimers}}.


open_bind_resp({data, [#pdu{} = Resp | _KnownPDU], _UnknownPDU}, #state{socket = Socket, mode = Mode, response_timers = Timers} = State) -> %% FIXME: proceed other known PDU
    case proceed_bind_resp(Resp, Mode) of
        {ok, NextState, Seq} ->
            NewTimers = case dict:find(Seq, Timers) of %% TODO: to utils
                            {ok, TimerRef} ->
                                erlang:cancel_timer(TimerRef),
                                dict:erase(Seq, Timers);
                            error ->
                                Timers
                        end,
            io:format("Connected!~n"),
            {next_state, NextState, State#state{response_timers = NewTimers}};
        {error, Error} ->
            io:format("Unable to connect: ~p~n", [Error]),
            {stop, normal};
        {unknown_command, Seq, CommandId, _Status} ->
            io:format("Received unknown PDU in unbinded: ~p~n", [CommandId]),
            Req = #generic_nack{},
            Code = ?ESME_RINVBNDSTS,
            gen_tcp:send(Socket, esmpp34raw:pack_single(Req, Code, Seq)),
            {next_state, open_bind_resp, State}
    end;

open_bind_resp(Signal, #state{} = State) ->
    io:format("===========> ~p~n", [Signal]),
    {next_state, open_bind_resp, State}.

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
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: term(), StateName :: atom(),
                  StateData :: term()) ->
             {next_state, NextStateName :: atom(), NewStateData :: term()} |
             {next_state, NextStateName :: atom(), NewStateData :: term(),
              timeout() | hibernate} |
             {stop, Reason :: normal | term(), NewStateData :: term()}).

handle_info(bind, StateName, #state{} = StateData) ->
    ?MODULE:StateName(bind, StateData);

handle_info({tcp, _Socket,  Bin}, StateName, #state{data = OldData} = StateData) ->
    io:format("data: ~p~n", [Bin]),
    {KnownPDU, UnknownPDU, Rest} = esmpp34raw:unpack_sequence(<<OldData/binary, Bin/binary>>),
    ?MODULE:StateName({data, KnownPDU, UnknownPDU}, StateData#state{data = Rest});

%% TODO: timers
%% handle_info({timeout, _TimerRef, {enquire_link, Seq}}, StateName, #state{response_timers = Timers} = State) ->
%%   NewTimers = handle_timeout(Seq, Timers),
%%   %% TODO: send error to logic
%%   {next_state, StateName, State#state{response_timers = NewTimers}}; %% FIXME: maybe stop

%% handle_info({timeout, _TimerRef, Seq}, _, #state{response_timers = Timers} = State) ->
%%   NewTimers = handle_timeout(Seq, Timers),
%%   {stop, normal, State#state{response_timers = NewTimers}}; %% FIXME: why stop?


handle_info({tcp_closed, _Socket}, _StateName, #state{response_timers = Timers} = State) ->
    io:format("Socket closed, cancelling timers...~n"),
    lists:foreach(fun(Timer) -> erlang:cancel_timer(Timer) end, dict:to_list(Timers)),
    {stop, normal, State#state{response_timers = []}}; %% FIXME: reconnect

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

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


starter(Host, Port, #state{} = State) ->
    case inet_parse:address(Host) of
        {ok, IpAddress} ->
            Options = [binary, {ip, IpAddress}, {packet, raw}, {active, true}, {reuseaddr, true}],
            case gen_tcp:connect(IpAddress, Port, Options, 30000) of %% TODO: timeout from config?
                {ok, Socket} ->
                    io:format("Connected to ~p:~p~n", [Host,Port]),
                    erlang:send_after(1, self(), bind),
                    {ok, open, State#state{socket = Socket}};
                {error, Reason} ->
                    io:format("TCP connect error start: ~p~n", [Reason]),
                    {stop, normal}
            end;
        _ ->
            io:format("Unable parse IP ~p, stopping client... ~n", [Host]),
            {stop, normal}
    end.

proceed_bind_resp(#pdu{sequence_number = Num, command_id = ?bind_transceiver_resp, command_status = Status}, Mode) when Mode == trx, Status == ?ESME_ROK ->
    {ok, transceiver, Num};
proceed_bind_resp(#pdu{sequence_number = _Num, command_id = ?bind_transceiver_resp, command_status = Status}, Mode) when Mode == trx, Status /= ?ESME_ROK ->
    {error, Status};
proceed_bind_resp(#pdu{sequence_number = Num, command_id = CommandId, command_status = Status}, _Mode)  ->
    {unknown_command, Num, CommandId, Status}.
