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
        erlang:apply(fun(#Name{Field = Value}) when Value /= undefined -> {ok, Field, Value};
                        (_) -> {error, Field, []} end,
                     [Record])).



-define(get_failed_mandatory(List),
        lists:filter(fun({ok, _, _}) -> false;
                        ({error, _}) -> true end, List)).



-define(check_subrecord(Name, Record, Field, Callback),
        erlang:apply(fun(#Name{Field = V}) -> case Callback(V) of 
						  [] -> [];
						  Errors -> {error, Field, Errors}
					      end;
                        (_) -> []
                     end,
                     [Record])).



%%--------------------------------------------------------------------
%% @doc
%% Checks, if the configuration is valid
%% @end
%%--------------------------------------------------------------------

-type config_entry() :: {Key :: binary(), Value :: term()
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

-spec(parse_config(Entries :: [config_entry()], Accumulator :: #config{}) ->
             #config{}).

parse_config([], #config{} = Config) ->
    Config;

parse_config([{<<"directions">>, Section} | RestSections], #config{} = Config) ->
    parse_config(RestSections, Config#config{directions = [parse_direction(Dir, #section_direction{}) || Dir <- Section]});

parse_config([{_UnknownSection, _} | RestSections], #config{} = Config) ->
    %% TODO: add warning
    parse_config(RestSections, Config).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Transforms the etoml representation of section "directions" to the
%% internal record format
%% @end
%%--------------------------------------------------------------------

-spec(parse_direction(Entries :: [config_entry()], Accumulator :: #section_direction{}) ->
             #section_direction{}).

parse_direction([], #section_direction{} = Direction) ->
    Direction;

parse_direction([{<<"id">>, Id} | RestOptions], #section_direction{} = Direction) when is_integer(Id) ->
    parse_direction(RestOptions, Direction#section_direction{id = Id});

parse_direction([{<<"mode">>, <<"transmitter">>} | RestOptions], #section_direction{} = Direction) ->
    parse_direction(RestOptions, Direction#section_direction{mode = transmitter});
parse_direction([{<<"mode">>, <<"receiver">>} | RestOptions], #section_direction{} = Direction) ->
    parse_direction(RestOptions, Direction#section_direction{mode = receiver});
parse_direction([{<<"mode">>, <<"transceiver">>} | RestOptions], #section_direction{} = Direction) ->
    parse_direction(RestOptions, Direction#section_direction{mode = transceiver});

parse_direction([{<<"loadsharing">>, LoadSharing} | RestOptions], #section_direction{} = Direction) when is_boolean(LoadSharing) ->
    parse_direction(RestOptions, Direction#section_direction{load_sharing = LoadSharing});

parse_direction([{<<"connections">>, Connections} | RestOptions], #section_direction{} = Direction) when is_list(Connections) ->
    parse_direction(RestOptions,
                    Direction#section_direction{connections = [parse_connection(Connect, #connection{}) || Connect <- Connections]});

parse_direction([{_UnknownOption, _} | RestOptions], #section_direction{} = Direction) ->
    %% TODO: add warning
    parse_direction(RestOptions, Direction).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Transforms the etoml representation of option "connections" to the
%% internal record format
%% @end
%%--------------------------------------------------------------------

-spec(parse_connection(Entries :: [config_entry()], Accumulator :: #connection{}) ->
             #connection{}).

parse_connection([], #connection{} = Connection) ->
    Connection;

parse_connection([{<<"type">>, <<"server">>} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{type = server});
parse_connection([{<<"type">>, <<"client">>} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{type = client});

parse_connection([{<<"login">>, Login} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{login = binary_to_list(Login)});

parse_connection([{<<"password">>, Password} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{password = binary_to_list(Password)});

parse_connection([{<<"response_timeout">>, ResponseTimeout} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{response_timeout = ResponseTimeout});

parse_connection([{<<"enquiry_link">>, EnquiryLinkInterval} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{el_interval = EnquiryLinkInterval});

parse_connection([{<<"host">>, Host} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{host = parse_host(Host)});

parse_connection([{_UnknownOption, _} | RestOptions], #connection{} = Connection) ->
    %% TODO: add warning
    parse_connection(RestOptions, Connection).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Transforms the host entry to the internal format
%% @end
%%--------------------------------------------------------------------

-spec(parse_host({Host :: binary(), Port :: 0..65535}) ->
             Ret :: {all, Port :: 0..65535}
                  | {Host::string(), Port :: 0..65535}).

parse_host({<<"all">>, Port}) when Port >= 0, Port =< 65535 ->
    {all, Port};

parse_host({Host, Port}) when is_binary(Host), Port >= 0, Port =< 65535 ->
    {binary_to_list(Host), Port}.



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
    ?get_failed_mandatory([?check_mandatory_field(config, Config, directions)]) ++
	?check_subrecord(config, Config, directions, fun check_section_direction/1).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Checks, if all the mandatory fields in #section_direction{} record is set
%% @end
%%--------------------------------------------------------------------

-spec(check_section_direction(Section :: #section_direction{}) ->
	     Errors :: []
		     | [{error, Field :: atom(), Error :: any() }]).

check_section_direction(#section_direction{} = Record) ->
    ?get_failed_mandatory([?check_mandatory_field(section_direction, Record, id),
                           ?check_mandatory_field(section_direction, Record, mode),
			   ?check_mandatory_field(section_direction, Record, connections)]) ++ 
	check_connection(Record#section_direction.connections, []).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Checks, if all the mandatory fields in #connection{} record is set
%% @end
%%--------------------------------------------------------------------

-spec(check_connection(ConnectionList :: undefined | [#connection{}], Accumulator :: [{error, Field :: atom(), Error :: any() }]) ->
	     Errors :: [] 
		     | [{error, Field :: atom(), Error :: any() }]).

check_connection(undefined, _) ->
    [];

check_connection([], Accumulator) ->
    lists:flatten(Accumulator);

check_connection([#connection{} = Record | Rest], Accumulator) ->
    Errors = ?get_failed_mandatory([?check_mandatory_field(connection, Record, type),
				    ?check_mandatory_field(connection, Record, host),
				    ?check_mandatory_field(connection, Record, login),
				    ?check_mandatory_field(connection, Record, password)]),
    check_connection(Rest, [Errors | Accumulator]).

