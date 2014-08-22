%%%-------------------------------------------------------------------
%%% @author morozov
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. Авг. 2014 10:21
%%%-------------------------------------------------------------------
-module(esmpp34_direction_sup).
-author("morozov").

-behaviour(supervisor).

%% API
-export([ start_link/0,
          start_direction/1 ]).

%% Supervisor callbacks
-export([init/1]).



-include("esmpp34.hrl").



-define(SERVER, ?MODULE).



%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------

-spec(start_link() ->
             {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).



%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @end
%%--------------------------------------------------------------------

-spec(init(Args :: term()) ->
             {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
                                MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
                   [ChildSpec :: supervisor:child_spec()]
                  }} |
             ignore |
             {error, Reason :: term()}).

init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 1000,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    {ok, {SupFlags, []}}.



%%%===================================================================
%%% Internal functions
%%%===================================================================

start_direction(#direction{id = Id} = Dir) ->
    DirSpec = {{esmpp34_direction, Id},
               {esmpp34_direction, start_link, [Dir]}, permanent, 3000, worker, [esmpp34_direction]},
    supervisor:start_child(?MODULE, DirSpec).