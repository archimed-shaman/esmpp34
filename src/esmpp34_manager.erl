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
-export([ start_link/1,
          run_config/0,
          register_direction/1 ]).

%% gen_server callbacks
-export([ init/1,
          handle_call/3,
          handle_cast/2,
          handle_info/2,
          terminate/2,
          code_change/3 ]).


-include("esmpp34.hrl").

-define(SERVER, ?MODULE).



-record(state, { callback,
                 config         = #config{},
                 pid_dict       = dict:new(),
                 direction_dict = dict:new() }).



-record(pid_record, { id                 :: non_neg_integer(),
                      monitor_ref = null :: reference() | null}).



-record(dir_record, { dir        :: #direction{},
                      connection_pid = [],
                      pid = null :: pid() | null }).



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

-spec(run_config() ->
             Rep :: ok
                  | {error, Error :: term()}).

run_config() ->
    gen_server:call(?SERVER, run_config).



%%--------------------------------------------------------------------
%% @doc
%% Register direction
%% @end
%%--------------------------------------------------------------------

-spec(register_direction(Id :: non_neg_integer()) ->
             Rep :: ok
                  | {error, Error :: term()}).

register_direction(Id) ->
    gen_server:call(?SERVER, {register_direction, Id}).



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
    {ok, #state{callback = CallBack}}.
%%     io:format("Checking config... ~n"),
%%     case get_config(CallBack()) of
%%         {ok, Config} ->
%%             io:format("Config check ok ~n"),
%%             case run_config(#config{}, Config, #state{callback = CallBack, config = Config}) of
%%                 #state{} = State ->
%%                     io:format("Managr started~n"),
%%                     {ok, State};
%%                 {error, Reason} ->
%%                     io:format("Managr error: ~p~n", [Reason]),
%%                     {stop, Reason}
%%             end;
%%         {error, Reason} ->
%%             io:format("Unable start manager: ~p~n", [Reason]),
%%             {stop, Reason}
%%     end.




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

handle_call(run_config, _From, #state{callback = Callback, config = OldConfig} = State) ->
    io:format("Checking config... ~n"),
    case get_config(Callback()) of
        {ok, NewConfig} ->
            io:format("Config check ok ~n"),
            case run_config(OldConfig, NewConfig, State) of
                #state{} = NewState ->
                    io:format("Done ~n"),
                    {reply, ok, NewState#state{config = NewConfig}};
                {error, Reason} ->
                    io:format("Error: ~p ~n", [Reason]),
                    {reply, {error, Reason}, State};
                Any ->
                    io:format("Hujnya: ~p ~n", [Any]),
                    {reply, {error, Any}, State}
            end;
        {error, Reason} -> {reply, {error, Reason}, State}
    end;

handle_call({register_direction, DirId}, {From, _}, #state{direction_dict = DirDict, pid_dict = PidDict} = State) ->
    case dict:find(DirId, DirDict) of
        {ok, #dir_record{dir = #direction{connections = ConnectionList}} = DirRec} ->
            MonitorRef = erlang:monitor(process, From),
            NewDirDict = dict:store(DirId, DirRec#dir_record{pid = From}, DirDict),
            NewPidDic = dict:store(From, #pid_record{id = DirId, monitor_ref = MonitorRef}, PidDict),
            %% try start connections
            lists:foreach(fun(ConnParam) -> start_connection(ConnParam, State) end, ConnectionList),
            {reply, ok, State#state{direction_dict = NewDirDict,
                                    pid_dict = NewPidDic }};
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
                                 %% FIXME: maybe ask stop
                                 lists:foreach(fun(Pid) -> erlang:exit(Pid, direction_down) end, ConnPids),
                                 dict:update(DirId, DirRec#dir_record{pid = null, connection_pid = []}, DirDict);
                             error ->
                                 DirDict
                         end,
            NewPidDict = dict:erase(DownPid, PidDict),
            {noreply, State#state{pid_dict = NewPidDict, direction_dict = NewDirDict}};
        error ->
            {noreply, State}
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



run_config(#config{} = _OldConfig, #config{} = NewConfig, #state{} = State) ->
    %% TODO: diff config and run diff
    io:format("run config~n"),
    NewState = lists:foldl(fun start_direction/2, State, NewConfig#config.directions),
    io:format("config done~n"),
    NewState.



get_config(RawConfig) ->
    case esmpp34_configuration:validate_configuration(RawConfig) of
        {error, _Reason} = Error -> Error;
        {#config{} = Config, []} -> {ok, Config};
        {#config{}, Errors} -> {error, Errors};
        Any -> {error, {unknown, Any}}
    end.


start_direction(#direction{id = DirId} = Dir,
                #state{direction_dict = DirDict} = CurrState) ->
    NewDirDict = dict:store(DirId, #dir_record{dir = Dir}, DirDict),
    io:format("Starting direction #~p...~n", [DirId]),
    esmpp34_direction_sup:start_direction(Dir),
    CurrState#state{direction_dict = NewDirDict}.


start_connection(#connection_param{id = Id},
                 #state{config = Config}) ->
    case lists:dropwhile(fun(#connection{id = ConnId}) -> ConnId /= Id end, Config#config.connections) of
        [] ->
            ok;
        [Connection | _] ->
            io:format("==> Starting connection ~p~n", [Connection]),
            esmpp34_connection_sup:start_connection(Connection)
    end.
