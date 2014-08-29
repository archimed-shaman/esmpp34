%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% Connection supervisor
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

-module(esmpp34_connection_sup).
-author("Alexander Morozov aka ~ArchimeD~").

-behaviour(supervisor).

%% API
-export([ start_link/0,
          start_connection/1 ]).

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

start_connection(#connection{type = server, id = Id} = Spec) ->
    ConnSpec = {{esmpp34_server, Id},
                {esmpp34_server, start_link, [Spec]}, permanent, 3000, worker, [esmpp34_server]},
    supervisor:start_child(?MODULE, ConnSpec);

start_connection(#connection{type = client, id = Id} = Spec) ->
    ok.
%%     ConnSpec = {{esmpp34_server, Id},
%%                 {esmpp34_server, start_link, [Spec]}, permanent, 3000, worker, [esmpp34_server]},
%%     supervisor:start_child(?MODULE, ConnSpec).