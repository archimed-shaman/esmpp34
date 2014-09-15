%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% Configuration processing module
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

-module(esmpp34_configuration).
-author("Alexander Morozov aka ~ArchimeD~").

%% API
-export([validate_configuration/1]).

-include("esmpp34.hrl").



%%--------------------------------------------------------------------
%% Macro helpers
%%--------------------------------------------------------------------



-define(check_mandatory_field(Name, Record, Field),
        erlang:apply(fun(#Name{Field = V}) when V /= undefined -> {ok, Field, V};
                        (_) -> {error, {Name, Field}, []} end,
                     [Record])).



-define(get_failed_mandatory(List),
        lists:filter(fun({ok, _, _}) -> false;
                        ({error, _, _}) -> true end, List)).



-define(check_subrecord(Name, Record, Field, Callback),
        erlang:apply(fun(#Name{Field = V}) -> case Callback(V) of
                                                  [] -> [];
                                                  Errors -> [{error, {Name, Field}, Errors}]
                                              end;
                        (_) -> []
                     end,
                     [Record])).



%%--------------------------------------------------------------------
%% @doc
%% Checks, if the configuration is valid
%% @end
%%--------------------------------------------------------------------

-type config_entry() :: {Key :: atom(), Value :: term()
                                               | [config_entry]}.
-spec(validate_configuration([config_entry()]) ->
             {ParsedConfig :: #config{}, Errors :: [] | [{error, Field :: atom(), Error :: any() }]} |
             {error, Reason :: term()}).

validate_configuration([]) ->
    {error, empty_configuration};

validate_configuration(Config) when is_list(Config) ->
    ParsedConfig = parse_config(Config, #config{}),
    Errors = check_config(ParsedConfig),
    {ParsedConfig, Errors}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Transforms the etoml representation of config to the internal record format
%% @end
%%--------------------------------------------------------------------

-spec(parse_config(Entries :: list(), Accumulator :: [#smpp_entity{}]) ->
             [#smpp_entity{}]).

parse_config([], Config) ->
    lists:reverse(Config);

parse_config([Head | Tail], Config) ->
    parse_config(Tail, [parse_entity(Head, #smpp_entity{}) | Config]).



parse_entity([], #smpp_entity{} = Entity) ->
    Entity;
parse_entity([{id, Id} | Tail], #smpp_entity{} = Entity) ->
    parse_entity(Tail, Entity#smpp_entity{id = Id});
parse_entity([{type, Type} | Tail], #smpp_entity{} = Entity) when Type == esme; Type == smsc ->
    parse_entity(Tail, Entity#smpp_entity{type = Type});
parse_entity([{system_id, SystemId} | Tail], #smpp_entity{} = Entity) ->
    parse_entity(Tail, Entity#smpp_entity{system_id = SystemId});
parse_entity([{password, Password} | Tail], #smpp_entity{} = Entity) ->
    parse_entity(Tail, Entity#smpp_entity{password = Password});
parse_entity([{host, Host} | Tail], #smpp_entity{} = Entity) ->
    parse_entity(Tail, Entity#smpp_entity{host = Host});
parse_entity([{port, Port} | Tail], #smpp_entity{} = Entity) ->
    parse_entity(Tail, Entity#smpp_entity{port = Port});
parse_entity([{allowed_modes, AllowedModes} | Tail], #smpp_entity{} = Entity) ->
    parse_entity(Tail, Entity#smpp_entity{allowed_modes = [X || X <- AllowedModes, X == tx, X == rx, X == trx]});
parse_entity([{port, Port} | Tail], #smpp_entity{} = Entity) ->
    parse_entity(Tail, Entity#smpp_entity{port = Port});
parse_entity([_ | Tail], #smpp_entity{} = Entity) ->
    %% TODO: warning for unknown field
    parse_entity(Tail, Entity#smpp_entity{}).





%%--------------------------------------------------------------------
%% @private
%% @doc
%% Checks, if all the mandatory fields in #config{} record is set
%% @end
%%--------------------------------------------------------------------

-spec(check_config(Config :: #config{}) ->
             Errors :: []
                     | [{error, Field :: atom(), Error :: any() }]).

check_config(#config{} = Config) ->
    E1 = ?get_failed_mandatory([?check_mandatory_field(config, Config, connections)]),
    E2 = ?get_failed_mandatory([?check_mandatory_field(config, Config, directions)]),
    E3 = ?check_subrecord(config, Config, directions, fun check_section_list/1),
    E4 = ?check_subrecord(config, Config, connections, fun check_section_list/1),
    E1 ++ E2 ++ E3 ++ E4.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Checks, if all the mandatory fields in the list of sections record is set
%% @end
%%--------------------------------------------------------------------

check_section_list(List) when is_list(List) ->
    check_section_list(List, []).

check_section_list([], Acc) ->
    Acc;

check_section_list([Section | Tail], Acc) ->
    check_section_list(Tail, Acc ++ check_section(Section)).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Checks, if all the mandatory fields in #section{} record is set
%% @end
%%--------------------------------------------------------------------

-spec(check_section(Section :: #direction{} | #connection{}) ->
             Errors :: []
                     | [{error, Field :: atom(), Error :: any() }]).

check_section(#direction{} = Record) ->
    ?get_failed_mandatory([?check_mandatory_field(direction, Record, id),
                           ?check_mandatory_field(direction, Record, mode),
                           ?check_mandatory_field(direction, Record, connections)]);

check_section(#connection{} = Record) ->
    ?get_failed_mandatory([?check_mandatory_field(connection, Record, id),
                           ?check_mandatory_field(connection, Record, type),
                           ?check_mandatory_field(connection, Record, host)]).
