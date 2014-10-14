%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% The module, which routes requests to workers and vice versa
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

-module(esmpp34_direction).
-author("Alexander Morozov aka ~ArchimeD~").

-behaviour(gen_server).

%% API
-export([
         start_link/1,
         register_connection/3,
         get_data/1,
         send_data/2,
         send_data/3,
         send_data/4
        ]).

%% gen_server callbacks
-export([
         init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
        ]).



-include("esmpp34.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_types.hrl").


-define(SERVER, ?MODULE).

-record(state, { dir :: #smpp_entity{},
                 tx :: pid(),
                 tx_ref,
                 rx :: pid(),
                 rx_ref,
                 pdu_buffer = [] }).



%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Start the server
%% @end
%%--------------------------------------------------------------------

-spec start_link(#smpp_entity{}) ->
                        {ok, Pid :: pid()} | ignore | {error, Reason :: term()}.


start_link(#smpp_entity{} = Dir) ->
    gen_server:start_link(?MODULE, [{dir, Dir}], []).



%%--------------------------------------------------------------------
%% @doc
%% Register the connection in direction as receiver, transmitter, or
%% trensceiver. Returns the pid of direcion, or error.
%% @end
%%--------------------------------------------------------------------

-spec register_connection(DirPid, Mode, Pid) -> Result when
      DirPid :: pid(),
      Mode :: tx | rx | trx,
      Pid :: pid(),
      Result :: {ok, pid()} | {error, already_bound}.


register_connection(DirPid, Mode, Pid) ->
    gen_server:call(DirPid, {register_connection, Mode, Pid}).



%%--------------------------------------------------------------------
%% @doc
%% Return the PDUs received
%% @end
%%--------------------------------------------------------------------

-spec get_data(DirPid) -> {ok, PduList} when
      DirPid :: pid(),
      PduList :: [] | [#pdu{}].


get_data(DirPid) ->
    gen_server:call(DirPid, get_data).



%%--------------------------------------------------------------------
%% @doc
%% Send PDU to the first suitable connection
%% @end
%%--------------------------------------------------------------------

-spec send_data(DirPid, Data) -> Resp when
      DirPid :: pid(),
      Data :: pdu_body(),
      Resp :: ok | {error, any()}.


send_data(DirPid, Data) ->
    gen_server:call(DirPid, {send_data, Data}).



%%--------------------------------------------------------------------
%% @doc
%% Send PDU to the first suitable connection
%% @end
%%--------------------------------------------------------------------

-spec send_data(DirPid, Data, Sequence) -> Resp when
      DirPid :: pid(),
      Data :: pdu_body(),
      Sequence :: non_neg_integer(),
      Resp :: ok | {error, any()}.


send_data(DirPid, Data, Sequence) ->
    gen_server:call(DirPid, {send_data, Data, Sequence}).



%%--------------------------------------------------------------------
%% @doc
%% Send PDU to the first suitable connection
%% @end
%%--------------------------------------------------------------------

-spec send_data(DirPid, Data, Sequence, Status) -> Resp when
      DirPid :: pid(),
      Data :: pdu_body(),
      Sequence :: non_neg_integer(),
      Status :: non_neg_integer(),
      Resp :: ok | {error, any()}.


send_data(DirPid, Data, Sequence, Status) ->
    gen_server:call(DirPid, {send_data, Data, Sequence, Status}).



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%% @end
%%--------------------------------------------------------------------

-spec init(Args :: term()) ->
                  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
                  {stop, Reason :: term()} | ignore.

init(Args) ->
    Direction = proplists:get_value(dir, Args),
    io:format("Direction #~p started~n", [Direction#smpp_entity.id]),
    erlang:send_after(1, self(), register),
    {ok, #state{dir = Direction}}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------

-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #state{}) ->
             {reply, Reply :: term(), NewState :: #state{}} |
             {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
             {noreply, NewState :: #state{}} |
             {noreply, NewState :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
             {stop, Reason :: term(), NewState :: #state{}}).


handle_call({register_connection, tx, Pid}, _From, #state{tx = Tx, tx_ref = TxRef} = State) when Tx == undefined, TxRef == undefined->
    Ref = erlang:monitor(process, Pid),
    {reply, {ok, self()}, State#state{tx = Pid, tx_ref = Ref}};

handle_call({register_connection, rx, Pid}, _From, #state{rx = Rx, rx_ref = RxRef} = State) when Rx == undefined, RxRef == undefined->
    Ref = erlang:monitor(process, Pid),
    {reply, {ok, self()}, State#state{rx = Pid, rx_ref = Ref}};

handle_call({register_connection, trx, Pid}, _From, #state{tx = Tx, tx_ref = TxRef,
                                                           rx = Rx, rx_ref = RxRef} = State)  when Tx == undefined, TxRef == undefined,
                                                                                                   Rx == undefined, RxRef == undefined ->
    io:format("Dir ~p registers ~p, Tx: ~p, Rx: ~p, TxRef: ~p, RxRef: ~p ~n", [self(), Pid, Tx, Rx, TxRef, RxRef]),
    Ref = erlang:monitor(process, Pid),
    {reply, {ok, self()}, State#state{tx = Pid, rx = Pid, rx_ref = Ref, tx_ref = Ref}};

handle_call({register_connection, _, _Pid}, _From, #state{} = State) ->
    {reply, {error, already_bound}, State};

handle_call({receive_data, Pdu}, _From, #state{pdu_buffer = PDUBuffer} = State) ->
    %% TODO: receive pdus as list
    {reply, ok, State#state{pdu_buffer = PDUBuffer ++ [Pdu]}};

handle_call(get_data, _From, #state{pdu_buffer = PDUBuffer} = State) ->
    {reply, {ok, PDUBuffer}, State#state{pdu_buffer = []}};

handle_call({send_data, Data}, {From, _}, #state{tx = Tx, rx = Rx} = State) ->
    Connections = lists:filter(fun(Pid) when Pid /= undefined -> true; (_) -> false end, [Tx , Rx]),
    case lists:dropwhile(fun(Pid) -> gen_fsm:sync_send_event(Pid, {send, Data, From}) /= ok end, Connections) of
        [] ->
            {reply, {error, no_awailable_connections}, State};
        [_|_] ->
            {reply, ok, State}
    end;

handle_call({send_data, Data, Sequence}, {From, _}, #state{tx = Tx, rx = Rx} = State) ->
    Connections = lists:filter(fun(Pid) when Pid /= undefined -> true; (_) -> false end, [Tx , Rx]),
    case lists:dropwhile(fun(Pid) -> gen_fsm:sync_send_event(Pid, {send, Data, From, Sequence}) /= ok end, Connections) of
        [] ->
            {reply, {error, no_awailable_connections}, State};
        [_|_] ->
            {reply, ok, State}
    end;

handle_call({send_data, Data, From, Sequence, Status}, _From, #state{tx = Tx, rx = Rx} = State) ->
    Connections = lists:filter(fun(Pid) when Pid /= undefined -> true; (_) -> false end, [Tx , Rx]),
    case lists:dropwhile(fun(Pid) -> gen_fsm:sync_send_event(Pid, {send, Data, From, Sequence, Status}) /= ok end, Connections) of
        [] ->
            {reply, {error, no_awailable_connections}, State};
        [_|_] ->
            {reply, ok, State}
    end.





%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%% @end
%%--------------------------------------------------------------------

-spec(handle_cast(Request :: term(), State :: #state{}) ->
             {noreply, NewState :: #state{}} |
             {noreply, NewState :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term(), NewState :: #state{}}).

handle_cast(_Request, State) ->
    {noreply, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------

-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
             {noreply, NewState :: #state{}} |
             {noreply, NewState :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term(), NewState :: #state{}}).

handle_info(register, #state{dir = Direction} = State) ->
    Res = esmpp34_manager:register_direction(Direction#smpp_entity.id),
    io:format("Direction #~p: trying to register: ~p~n",[Direction#smpp_entity.id, Res]),
    {noreply, State};

handle_info({'DOWN', MonitorRef, process, DownPid, _},
            #state{tx = Tx, rx = Rx, tx_ref = TxRef, rx_ref = RxRef} = State) when DownPid == Tx, MonitorRef == TxRef,
                                                                                   DownPid == Rx, MonitorRef == RxRef ->
    {noreply, State#state{tx = undefined, rx = undefined, tx_ref = undefined, rx_ref = undefined}};

handle_info({'DOWN', MonitorRef, process, DownPid, _},
            #state{tx = Tx, tx_ref = TxRef} = State) when DownPid == Tx, MonitorRef == TxRef ->
    {noreply, State#state{tx = undefined, tx_ref = undefined}};

handle_info({'DOWN', MonitorRef, process, DownPid, _},
            #state{rx = Rx, rx_ref = RxRef} = State) when DownPid == Rx, MonitorRef == RxRef ->
    {noreply, State#state{rx = undefined, rx_ref = undefined}};

%% TODO: remove this, let it fall
handle_info(Info, State) ->
    io:format("~p: ~p~n", [?MODULE, Info]),
    {noreply, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
%%--------------------------------------------------------------------

-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #state{}) -> term()).

terminate(_Reason, _State) ->
    ok.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------

-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
                  Extra :: term()) ->
             {ok, NewState :: #state{}} | {error, Reason :: term()}).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%%===================================================================
%%% Internal functions
%%%===================================================================
