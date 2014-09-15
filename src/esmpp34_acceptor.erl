%%%-------------------------------------------------------------------
%%% @author morozov
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. Авг. 2014 13:39
%%%-------------------------------------------------------------------
-module(esmpp34_acceptor).
-author("morozov").

-include("esmpp34.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_types.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_constants.hrl").

-behaviour(gen_fsm).

%% API
-export([start_link/3]).

%% gen_fsm callbacks
-export([ init/1,
          open/2,
          state_name/3,
          handle_event/3,
          handle_sync_event/4,
          handle_info/3,
          terminate/3,
          code_change/4 ]).

-define(SERVER, ?MODULE).

-record(state, { id,
                 socket,
                 el_timer,
                 connection,
                 response_timers = dict:new(),
                 data = <<>> }).



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

handle_info({tcp, _Socket,  Bin}, StateName, #state{data = OldData} = StateData) ->
    io:format("data: ~p~n", [Bin]),
    {KnownPDU, UnknownPDU, Rest} = esmpp34raw:unpack_sequence(<<OldData/binary, Bin/binary>>),
    ?MODULE:StateName({data, KnownPDU, UnknownPDU}, StateData#state{data = Rest});

handle_info({timeout, _TimerRef, {enquire_link, Seq}}, StateName, #state{response_timers = Timers} = State) ->
    NewTimers = handle_timeout(Seq, Timers),
    %% TODO: send error to logic
    {next_state, StateName, State#state{response_timers = NewTimers}};

handle_info({timeout, _TimerRef, Seq}, _, #state{response_timers = Timers} = State) ->
    NewTimers = handle_timeout(Seq, Timers),
    {stop, normal, State#state{response_timers = NewTimers}};

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

handle_timeout(Seq, Timers) ->
    case dict:find(Seq, Timers) of
        {ok, Timer} ->
            erlang:cancel_timer(Timer),
            dict:erase(Seq, Timers);
        error ->
            Timers
    end.



proceed_open(#state{connection = #smpp_entity{id = ConnectionId, el_interval = ElTimer} = Connection, socket = Socket} = State,
                #pdu{sequence_number = Seq, body = #bind_transceiver{password = Password, system_id = SystemId} = Packet}) ->
    io:format("===> TRANSCEIVER: ~p~n", [Packet]),
    Result = esmpp34_manager:register_connection(ConnectionId, transceiver, SystemId, Password),
    io:format("result of login: ~p~n", [Result]),
    {next_state, open, State};
%%     case esmpp34_l_bind:bind_request(Direction, Packet) of
%%         {ok, Code, Resp} ->
%%             gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
%%             {next_state, bound_trx, State, ElTimer};
%%         {error, Code, Resp} ->
%%             gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
%%     {stop, normal, State} %% FIXME: do something
%%     end;

proceed_open(#state{connection = #smpp_entity{} = Connection, socket = Socket} = State,
                #pdu{sequence_number = Seq, body = #bind_transmitter{} = Packet}) ->
    io:format("===> TRANSMITTER: ~p~n", [Packet]),
    {next_state, open, State};

proceed_open(#state{connection = #smpp_entity{} = Connection, socket = Socket} = State,
                #pdu{sequence_number = Seq, body = #bind_receiver{} = Packet}) ->
    io:format("===> RECEIVER: ~p~n", [Packet]),
    {next_state, open, State};

proceed_open(#state{} = State, A) ->
    io:format("error received unknown packet ~p~n", [A]),
    {next_state, open, State}.