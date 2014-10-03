%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% The main module
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

-module(esmpp34).
-author("Alexander Morozov aka ~ArchimeD~").


-include_lib("esmpp34raw/include/esmpp34raw_types.hrl").

%% API
-export([
         start/1,
         get_data/1
        ]).


%% TODO: write spec an @doc

start(ConfigGetter) when is_function(ConfigGetter) ->
    %% FIXME: match ok results
    application:start(esmpp34),
    esmpp34_sup:start_manager(ConfigGetter),
    esmpp34_manager:run_config().



%%--------------------------------------------------------------------
%% @doc
%% Get all PDUs, received by the direction
 %% @end
 %%--------------------------------------------------------------------

 -spec get_data(DirectionId) -> {ok, Data} | {error, Error} when
       DirectionId :: non_neg_integer(),
       Data :: [] | [#pdu{}],
       Error :: any().


get_data(DirectionId) ->
    case esmpp34_manager:get_direction_pid(DirectionId) of
        {ok, Pid} ->
            esmpp34_direction:get_data(Pid);
        {error, _} = Error ->
            Error
    end.
