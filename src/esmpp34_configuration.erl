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

-type config_entry() :: {Key :: binary(), Value :: binary()
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
    parse_config(RestSections, Config#config{directions = [parse_direction(Dir, #direction{}) || Dir <- Section]});

parse_config([{<<"connections">>, Section} | RestSections], #config{} = Config) ->
    parse_config(RestSections, Config#config{connections = [parse_connection(Conn, #connection{}) || Conn <- Section]});

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

-spec(parse_direction(Entries :: [config_entry()], Accumulator :: #direction{}) ->
             #direction{}).

parse_direction([], #direction{} = Direction) ->
    Direction;

parse_direction([{<<"id">>, Id} | RestOptions], #direction{} = Direction) ->
    parse_direction(RestOptions, Direction#direction{id = binary_to_integer(Id)});

parse_direction([{<<"mode">>, <<"transmitter">>} | RestOptions], #direction{} = Direction) ->
    parse_direction(RestOptions, Direction#direction{mode = transmitter});
parse_direction([{<<"mode">>, <<"receiver">>} | RestOptions], #direction{} = Direction) ->
    parse_direction(RestOptions, Direction#direction{mode = receiver});
parse_direction([{<<"mode">>, <<"transceiver">>} | RestOptions], #direction{} = Direction) ->
    parse_direction(RestOptions, Direction#direction{mode = transceiver});

parse_direction([{<<"loadsharing">>, <<"true">>} | RestOptions], #direction{} = Direction) ->
    parse_direction(RestOptions, Direction#direction{load_sharing = true});
parse_direction([{<<"loadsharing">>, <<"false">>} | RestOptions], #direction{} = Direction) ->
    parse_direction(RestOptions, Direction#direction{load_sharing = false});

parse_direction([{<<"connections">>, Connections} | RestOptions], #direction{} = Direction) when is_list(Connections) ->
    parse_direction(RestOptions,
                    Direction#direction{connections = [binary_to_integer(ConnId) || ConnId <- Connections]});

parse_direction([{_UnknownOption, _} | RestOptions], #direction{} = Direction) ->
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

parse_connection([{<<"id">>, Id} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{id = binary_to_integer(Id)});

parse_connection([{<<"type">>, <<"server">>} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{type = server});
parse_connection([{<<"type">>, <<"client">>} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{type = client});

parse_connection([{<<"login">>, Login} | RestOptions], #connection{login = undefined} = Connection) when is_list(Login) ->
    parse_connection(RestOptions, Connection#connection{login = parse_login(Login)});
parse_connection([{<<"login">>, Login} | RestOptions], #connection{login = LoginList} = Connection) when is_list(Login) ->
    parse_connection(RestOptions, Connection#connection{login = LoginList ++ parse_login(Login)});

parse_connection([{<<"response_timeout">>, ResponseTimeout} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{response_timeout = binary_to_integer(ResponseTimeout)});

parse_connection([{<<"enquiry_link">>, EnquiryLinkInterval} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{el_interval = binary_to_integer(EnquiryLinkInterval)});

parse_connection([{<<"host">>, Host} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{host = parse_host(Host)});

parse_connection([{<<"in_bandwidth">>, <<"unlimited">>} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{in_bandwidth = unlimited});
parse_connection([{<<"in_bandwidth">>, InBandwidth} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{in_bandwidth = binary_to_integer(InBandwidth)});

parse_connection([{<<"out_bandwidth">>, <<"unlimited">>} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{out_bandwidth = unlimited});
parse_connection([{<<"out_bandwidth">>, OutBandwidth} | RestOptions], #connection{} = Connection) ->
    parse_connection(RestOptions, Connection#connection{out_bandwidth = binary_to_integer(OutBandwidth)});

parse_connection([{_UnknownOption, _} | RestOptions], #connection{} = Connection) ->
    %% TODO: add warning
    parse_connection(RestOptions, Connection).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Transforms the host entry to the internal format
%% @end
%%--------------------------------------------------------------------

-spec(parse_host({Host :: binary(), Port :: binary()}) ->
             Ret :: {all, Port :: 0..65535}
                  | {Host::string(), Port :: 0..65535}).

parse_host([<<"all">>, Port]) ->
    {all, binary_to_integer(Port)};

parse_host([Host, Port]) when is_binary(Host) ->
    {binary_to_list(Host), binary_to_integer(Port)}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Transforms the login entry to the internal format
%% @end
%%--------------------------------------------------------------------

parse_login(List) ->
    parse_login(List, []).


-type login_list() :: [binary()].
-spec(parse_login(LoginList :: login_list() | [login_list()] | [],
                  Accumulator :: [{string(), string()}]) ->
             Ret :: [{Login::string(), Password :: string()}]).

parse_login([], Acc) ->
    lists:reverse(Acc);

parse_login([[Login, Password] | Tail], Acc) ->
    parse_login(Tail, [{binary_to_list(Login), binary_to_list(Password)} | Acc]);

parse_login([Login, Password], _) when is_binary(Login) and is_binary(Password)->
    [{binary_to_list(Login), binary_to_list(Password)}].

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
                           ?check_mandatory_field(connection, Record, host),
                           ?check_mandatory_field(connection, Record, login)]).
