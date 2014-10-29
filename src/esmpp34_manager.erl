%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% Configuration manager
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

-module(esmpp34_manager).
-author("morozov").

-behaviour(gen_server).

%% API
-export([
         start_link/1,
         get_status/0,
         register_direction/1,
         register_connection/2,
         register_connection/4,
         get_direction_pid/1
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

-define(SERVER, ?MODULE).



-record(state, { callback,
                 config         = [],
                 pid_dict       = dict:new(),
                 direction_dict = dict:new(),
                 status = initial }).



-record(pid_record, { id                 :: non_neg_integer(),
                      monitor_ref = null :: reference() | null}).



-record(dir_record, { dir                   :: #smpp_entity{},
                      connection_pid = [],
                      pid            = null :: pid() | null }).



%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------

-spec(start_link(Callback :: fun(() -> list())) ->
             {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).


start_link(Callback) when is_function(Callback) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [{callback, Callback}], []).



%%--------------------------------------------------------------------
%% @doc
%% Set the SMPP configuration and execute it
%% @end
%%--------------------------------------------------------------------

-spec get_status() -> Resp when
      Resp :: ok | {error, Error :: term()}.


get_status() ->
    gen_server:call(?SERVER, get_status).



%%--------------------------------------------------------------------
%% @doc
%% Register direction
%% @end
%%--------------------------------------------------------------------

-spec register_direction(Id) -> Resp when
      Id :: non_neg_integer(),
      Resp :: ok | {error, Error :: term()}.


register_direction(Id) ->
    gen_server:call(?SERVER, {register_direction, Id}).



%%--------------------------------------------------------------------
%% @doc
%% Register outgoing connection
%% @end
%%--------------------------------------------------------------------

-spec register_connection(ConnectionId, Mode) -> Resp when
      ConnectionId :: non_neg_integer(),
      Mode :: tx | rx | trx,
      Resp :: ok | {error, Error :: term()}.


register_connection(ConnectionId, Mode) ->
    gen_server:call(?SERVER, {register_connection, ConnectionId, Mode}).



%%--------------------------------------------------------------------
%% @doc
%% Register incoming connection
%% @end
%%--------------------------------------------------------------------

-spec register_connection(ConnectionId, Mode, Login, Password) -> Resp when
      ConnectionId :: non_neg_integer(),
      Mode :: tx | rx | trx,
      Login :: string(),
      Password :: string(),
      Resp :: ok | {error, Error :: term()}.


register_connection(ConnectionId, Mode, Login, Password) ->
    gen_server:call(?SERVER, {register_connection, ConnectionId, Mode, Login, Password}).



%%--------------------------------------------------------------------
%% @doc
%% Return the pid of the specified direction gen_server
%% @end
%%--------------------------------------------------------------------

-spec get_direction_pid(DirectionId) -> Resp when
      DirectionId :: non_neg_integer(),
      Resp :: {ok, pid()} | {error, no_direction} | {error, direction_down}.


get_direction_pid(DirectionId) ->
    gen_server:call(?SERVER, {get_direction_pid, DirectionId}).



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%% @end
%%--------------------------------------------------------------------

-spec(init(Args :: term()) ->
             {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term()} | ignore).

init(Args) ->
    io:format("Starting manager... ~n"),
    CallBack = proplists:get_value(callback, Args),
    erlang:send_after(1, self(), run_config),
    {ok, #state{callback = CallBack}}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
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

handle_call(get_status, _From, #state{status = Status} = State) ->
    {reply, Status, State};

handle_call({register_direction, DirId}, {From, _}, #state{direction_dict = DirDict, pid_dict = PidDict} = State) ->
    %%     {reply, {error, no_direction}, State};
    case dict:find(DirId, DirDict) of
        {ok, #dir_record{dir = Entity} = DirRec} ->
            MonitorRef = erlang:monitor(process, From),
            NewDirDict = dict:store(DirId, DirRec#dir_record{pid = From}, DirDict),
            NewPidDic = dict:store(From, #pid_record{id = DirId, monitor_ref = MonitorRef}, PidDict),
            %% try start connections
            start_connections(Entity),
            {reply, ok, State#state{direction_dict = NewDirDict,
                                    pid_dict = NewPidDic }};
        error ->
            {reply, {error, no_direction}, State}
    end;

handle_call({register_connection, ConnectionId, Mode}, {From, _}, #state{direction_dict = Directions} = State) ->
    case dict:find(ConnectionId, Directions) of
        {ok, #dir_record{dir = #smpp_entity{}, pid = DirPid}} ->
            Reply = esmpp34_direction:register_connection(DirPid, Mode, From),
            {reply, Reply, State};
        error ->
            {reply, {error, internal_error}, State}
    end;

handle_call({register_connection, ConnectionId, Mode, RSystemId, RPassword}, {From, _}, #state{direction_dict = Directions} = State) ->
    case dict:find(ConnectionId, Directions) of
        {ok, #dir_record{dir = #smpp_entity{type = smsc, system_id = SystemId, password = Password}, pid = DirPid}} when SystemId == RSystemId,
                                                                                                                         Password == RPassword ->
            Reply = esmpp34_direction:register_connection(DirPid, Mode, From),
            {reply, Reply, State};
        {ok, #dir_record{dir = #smpp_entity{type = esme, outbind = #outbind_field{system_id = SystemId, password = Password}}, pid = DirPid}} when SystemId == RSystemId,
                                                                                                                                                   Password == RPassword ->
            Reply = esmpp34_direction:register_connection(DirPid, Mode, From),
            {reply, Reply, State};
        {ok, #dir_record{dir = #smpp_entity{type = smsc, system_id = SystemId}}} when SystemId == RSystemId ->
            {reply, {error, password}, State};
        {ok, _} ->
            {reply, {error, system_id}, State};
        error ->
            {reply, {error, system_id}, State}
    end;

handle_call({get_direction_pid, DirectionId}, _From, #state{direction_dict = Directions} = State) ->
    case dict:find(DirectionId, Directions) of
        {ok, #dir_record{pid = DirPid}} ->
            {reply, {ok, DirPid}, State};
        error ->
            {reply, {error, no_direction}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, ok, State}.



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

handle_info({'DOWN', MonitorRef, process, DownPid, _}, #state{pid_dict = PidDict, direction_dict = DirDict} = State)->
    case dict:find(DownPid, PidDict) of
        {ok, #pid_record{id = DirId, monitor_ref = MonitorRef}} ->
            NewDirDict = case dict:find(DirId, DirDict) of
                             {ok, #dir_record{connection_pid = ConnPids} = DirRec} ->
                                 %% if direction crashed, kill all dependent connections

                                 %% FIXME: connection_pid is deprecated and always empty, rewrite this
                                 %% all client and accpeted connections will be stopped to, as they monitor the direction
                                 %% the main problem - to shut down correctly all the listeners, as there can be only one
                                 %% lisener for several connection. The listener should be stopped only if all other
                                 %% directions are down

                                 lists:foreach(fun(Pid) -> erlang:exit(Pid, direction_down) end, ConnPids),
                                 dict:store(DirId, DirRec#dir_record{pid = null, connection_pid = []}, DirDict);
                             error ->
                                 DirDict
                         end,
            NewPidDict = dict:erase(DownPid, PidDict),
            {noreply, State#state{pid_dict = NewPidDict, direction_dict = NewDirDict}};
        error ->
            {noreply, State}
    end;

handle_info(run_config, #state{callback = Callback, config = OldConfig} = State) ->
    %%     {reply, {error, error}, State};
    io:format("Checking config... ~n"),
    case get_config(Callback()) of
        {ok, NewConfig} ->
            io:format("Config check ok ~n"),
            case run_config(OldConfig, NewConfig, State) of
                #state{} = NewState ->
                    io:format("Done ~n"),
                    {noreply, NewState#state{status = ok, config = NewConfig}};
                {error, Reason} ->
                    io:format("Error: ~p ~n", [Reason]),
                    {noreply, State#state{status = {error, Reason}}};
                Any ->
                    io:format("Hujnya: ~p ~n", [Any]),
                    {noreply, State#state{status = {error, Any}}}
            end;
        {error, Reason} -> {noreply, State#state{status = {error, Reason}}}
    end;

handle_info(_Info, State) ->
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



run_config(_OldConfig, [_|_] = NewConfig, #state{} = State) ->
    %% TODO: diff config and run diff
    io:format("run config~n"),
    NewState = lists:foldl(fun start_direction/2, State, NewConfig),
    io:format("config done~n"),
    NewState.


get_config(RawConfig) ->
    case esmpp34_configuration:validate_configuration(RawConfig) of
        {error, _Reason} = Error -> Error;
        {[_|_] = Config, []} -> {ok, Config};
        {_Config, Errors} -> {error, Errors};
        Any -> {error, {unknown, Any}}
    end.


start_direction(#smpp_entity{id = DirId} = Dir,
                #state{direction_dict = DirDict} = CurrState) ->
    NewDirDict = dict:store(DirId, #dir_record{dir = Dir}, DirDict),
    Res = esmpp34_direction_sup:start_direction(Dir),
    io:format("Starting direction #~p... ~p~n", [DirId, Res]),
    CurrState#state{direction_dict = NewDirDict}.




start_connections(#smpp_entity{type = esme,
                               allowed_modes = Modes,
                               id = _Id,
                               host = Host,
                               port = Port,
                               outbind = Outbind} = Entity) ->
    FilteredModes = filter_modes(Modes),
    io:format("==> ESME: ~p, Filtered: ~p~n", [Modes, FilteredModes]),
    lists:foreach(fun(Mode) -> esmpp34_connection_sup:start_connection(client, Host, Port, Entity, Mode) end, FilteredModes),
    start_outbind(server, Outbind, Entity),
    ok;

start_connections(#smpp_entity{type = smsc,
                               allowed_modes = Modes,
                               id = _Id,
                               host = Host,
                               port = Port,
                               outbind = Outbind} = Entity) ->
    io:format("==> SMSC: ~p~n", [Modes]),
    esmpp34_connection_sup:start_connection(server, Host, Port, Entity, all), %% one listener for all modes
    start_outbind(client, Outbind, Entity), %% FIXME: open client outbind connection only on demand
    ok.


start_outbind(Mode, #outbind_field{host = OutbindHost, port = OutbindPort}, #smpp_entity{} = Entity) when Mode == client ->
    esmpp34_connection_sup:start_connection(Mode, OutbindHost, OutbindPort, Entity, tx);

start_outbind(Mode, #outbind_field{host = OutbindHost, port = OutbindPort}, #smpp_entity{} = Entity) when Mode == server ->
    esmpp34_connection_sup:start_connection(Mode, OutbindHost, OutbindPort, Entity, rx);

start_outbind(Mode, _, #smpp_entity{}) when Mode == server; Mode == client ->
    ok.






filter_modes(M) ->
    filter_modes(M, []).



filter_modes([tx | T], A) ->
    filter_modes (T, [tx | A]);
filter_modes([rx | T], A) ->
    filter_modes (T, [rx | A]);
filter_modes([trx | _], _) ->
    [trx];
filter_modes([], A) ->
    lists:reverse(A).
