%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% The main supervisor
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

-module(esmpp34_sup).
-author("Alexander Morozov aka ~ArchimeD~").



-behaviour(supervisor).

%% API
-export([start_link/0,
         start_config_holder/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define (SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% TODO: make config holder with
%% 1) CallBack
%% 2) Pure signal intercommunication (fsm)
%% 3) static configuration
start_config_holder(CallBack) when is_function(CallBack) ->
    ConfigHolder = {esmpp34_config_holder_cb,
                    {esmpp34_config_holder_cb, start_link, [{callback, CallBack}]}, permanent, 5000, worker, [esmpp34_config_holder_cb]},
    supervisor:start_child(?MODULE, ConfigHolder);

start_config_holder(Pid) when is_pid(Pid) ->
    ConfigHolder = {esmpp34_config_holder,
                    {esmpp34_config_holder, start_link, [{pid, Pid}]}, permanent, 5000, worker, [esmpp34_config_holder]},
    supervisor:start_child(?MODULE, ConfigHolder).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    Router = ?CHILD(esmpp34_router, worker),
    ConnectionSup = ?CHILD(esmpp34_connection_sup, supervisor),
    {ok, { {one_for_one, 5, 10}, [Router, ConnectionSup]}}.
