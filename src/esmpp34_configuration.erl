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
%% @doc
%% Check, if the configuration is valid
%% @end
%%--------------------------------------------------------------------

-type config_entry() :: {Key :: atom(), Value :: term()
                                               | [config_entry]}.
-spec(validate_configuration([config_entry()]) ->
             {ParsedConfig :: [#smpp_entity{}], Errors :: [] | [{error, Field :: atom(), Error :: any() }]} |
             {error, Reason :: term()}).


validate_configuration([]) ->
    {error, empty_configuration};

validate_configuration(Config) when is_list(Config) ->
    ParsedConfig = parse_config(Config, []),
    Errors = check_config(ParsedConfig, []),
    {ParsedConfig, Errors}.



%%%===================================================================
%%% Internal functions
%%%===================================================================


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Transform the list representation of config to the internal record format
%% @end
%%--------------------------------------------------------------------

-spec(parse_config(Entries :: list(), Accumulator :: [#smpp_entity{}]) ->
             [#smpp_entity{}]).


parse_config([], Config) ->
    lists:reverse(Config);

parse_config([Head | Tail], Config) ->
    parse_config(Tail, [parse_entity(Head, #smpp_entity{}) | Config]).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Fill smpp_entity record's fields from the given proplist
%% @end
%%--------------------------------------------------------------------

-spec parse_entity(PropertyList, Accumulator) -> Entity when
      PropertyList :: [{Key, Value}],
      Key :: atom(),
      Value :: any(),
      Accumulator :: #smpp_entity{},
      Entity :: #smpp_entity{}.


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
    parse_entity(Tail, Entity#smpp_entity{allowed_modes = [X || X <- AllowedModes]});

parse_entity([{outbind, Outbind} | Tail], #smpp_entity{} = Entity) ->
    parse_entity(Tail, Entity#smpp_entity{outbind = parse_outbind(Outbind)});

parse_entity([_ | Tail], #smpp_entity{} = Entity) ->
    %% TODO: warning for unknown field
    parse_entity(Tail, Entity#smpp_entity{}).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Fill outbind_field record's fields from the given proplist
%% @end
%%--------------------------------------------------------------------

-spec parse_outbind(PropertyList) -> Outbind when
      PropertyList :: [{Key, Value}],
      Key :: atom(),
      Value :: any(),
      Outbind :: #outbind_field{}.


parse_outbind(Data) ->
    parse_outbind(Data, #outbind_field{}).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Fill outbind_field record's fields from the given proplist
%% @end
%%--------------------------------------------------------------------

-spec parse_outbind(PropertyList, Accumulator) -> Outbind when
      PropertyList :: [{Key, Value}],
      Key :: atom(),
      Value :: any(),
      Accumulator :: #outbind_field{},
      Outbind :: #outbind_field{}.


parse_outbind([], #outbind_field{} = Outbind) ->
  Outbind;

parse_outbind([{system_id, SystemId} | Tail], #outbind_field{} = Outbind) ->
    parse_outbind(Tail, Outbind#outbind_field{system_id = SystemId});

parse_outbind([{password, Password} | Tail], #outbind_field{} = Outbind) ->
    parse_outbind(Tail, Outbind#outbind_field{password = Password});

parse_outbind([{host, Host} | Tail], #outbind_field{} = Outbind) ->
    parse_outbind(Tail, Outbind#outbind_field{host = Host});

parse_outbind([{port, Port} | Tail], #outbind_field{} = Outbind) ->
  parse_outbind(Tail, Outbind#outbind_field{port = Port}).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check, if all the mandatory fields in #config{} record are set,
%% and check fields for validity.
%% @end
%%--------------------------------------------------------------------

-spec check_config(Config, Accumulator) -> Errors when
      Config :: [#smpp_entity{}],
      Accumulator :: ErrorList,
      Errors :: ErrorList,
      ErrorList :: [] | [{error, Field, Error}],
      Field :: atom(),
      Error :: any().
      

check_config([], Accumulator) ->
    lists:flatten(lists:reverse(Accumulator));
    
check_config([ConfigEntry | Config], Accumulator) ->
    Errors = get_failed_fields(ConfigEntry),
    check_config(Config, [Errors | Accumulator]).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Construct a checker list and find any errors in fields
%% @end
%%--------------------------------------------------------------------

-spec get_failed_fields(SmppEntity) -> Errors when
      SmppEntity :: #smpp_entity{},
      Errors :: [] | [{error, string()}].


get_failed_fields(#smpp_entity{} = Entity) ->
    CheckList = [%% mandatory
                 fun check_id/1,
                 fun check_type/1,
                 fun check_system_id/1,
                 fun check_password/1,
                 fun check_host/1,
                 fun check_port/1,
                 fun check_allowed_modes/1,
                 %%optional
                 fun check_outbind/1
                ],
    lists:flatten([Checker(Entity) || Checker <- CheckList]).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check mandatory field 'id'
%% @end
%%--------------------------------------------------------------------

-spec check_id(SmppEntity) -> Error when
      SmppEntity :: #smpp_entity{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_id(#smpp_entity{id = Id}) when is_number(Id) -> %% TODO: make Id as any atom
    [];
check_id(#smpp_entity{id = Id}) when Id /= undefined ->
    {error, "'id' has wrong type", Id};
check_id(_) ->
    {error, "id is not set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check mandatory field 'type'
%% @end
%%--------------------------------------------------------------------

-spec check_type(SmppEntity) -> Error when
      SmppEntity :: #smpp_entity{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_type(#smpp_entity{type = Type}) when Type == smsc; Type == esme -> 
    [];
check_type(#smpp_entity{type = Type}) when Type /= undefined ->
    {error, "'type' has wrong value", Type};
check_type(_) ->
    {error, "'type' is no set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check mandatory field 'system_id'
%% @end
%%--------------------------------------------------------------------

-spec check_system_id(SmppEntity) -> Error when
      SmppEntity :: #smpp_entity{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_system_id(#smpp_entity{system_id = SystemId}) when is_list(SystemId) -> 
    [];
check_system_id(#smpp_entity{system_id = SystemId}) when SystemId /= undefined ->
    {error, "'system_id' has wrong type", SystemId};
check_system_id(_) ->
    {error, "'system_id' is no set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check mandatory field 'password'
%% @end
%%--------------------------------------------------------------------

-spec check_password(SmppEntity) -> Error when
      SmppEntity :: #smpp_entity{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_password(#smpp_entity{password = Password}) when is_list(Password) -> 
    [];
check_password(#smpp_entity{password = Password}) when Password /= undefined ->
    {error, "'password' has wrong type", Password};
check_password(_) ->
    {error, "'password' is no set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check mandatory field 'host'
%% @end
%%--------------------------------------------------------------------

-spec check_host(SmppEntity) -> Error when
      SmppEntity :: #smpp_entity{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_host(#smpp_entity{host = Host}) when is_list(Host); Host == all -> 
    [];
check_host(#smpp_entity{host = Host}) when Host /= undefined ->
    {error, "'host' has wrong type", Host};
check_host(_) ->
    {error, "'host' is no set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check mandatory field 'port'
%% @end
%%--------------------------------------------------------------------

-spec check_port(SmppEntity) -> Error when
      SmppEntity :: #smpp_entity{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_port(#smpp_entity{port = Port}) when is_number(Port), Port >= 0, Port =< 65535 ->
    [];
check_port(#smpp_entity{port = Port}) when Port /= undefined ->
    {error, "'port' has wrong type or value", Port};
check_port(_) ->
    {error, "port is not set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check mandatory field 'allowed_modes'
%% @end
%%--------------------------------------------------------------------

-spec check_allowed_modes(SmppEntity) -> Error when
      SmppEntity :: #smpp_entity{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().

check_allowed_modes(#smpp_entity{allowed_modes = [_|_]  = AllowedModes}) ->
    case lists:filter(fun(M) when M == tx; M == rx; M == trx -> false;
                         (_) -> true
                      end, AllowedModes) of
        [] -> [];
        UnknownValues -> {error, "'allowed_modes' has unknown values", UnknownValues}
    end;
    
check_allowed_modes(#smpp_entity{allowed_modes = []}) ->
    {error, "'allowed_modes' field is empty list"};

check_allowed_modes(_) ->
    {error, "'allowed_modes' is not set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check optional field 'outbind'
%% @end
%%--------------------------------------------------------------------

-spec check_outbind(SmppEntity) -> Error when
      SmppEntity :: #smpp_entity{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_outbind(#smpp_entity{outbind = Outbind}) when Outbind /= undefined ->
    CheckList = [fun check_outbind_system_id/1,
                 fun check_outbind_password/1,
                 fun check_outbind_host/1,
                 fun check_outbind_port/1],
    lists:flatten([Checker(Outbind) || Checker <- CheckList]);

check_outbind(_) ->
    [].



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check field 'system_id' in outbind
%% @end
%%--------------------------------------------------------------------

-spec check_outbind_system_id(Outbind) -> Error when
      Outbind :: #outbind_field{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_outbind_system_id(#outbind_field{system_id = SystemId}) when is_list(SystemId) -> 
    [];
check_outbind_system_id(#outbind_field{system_id = SystemId}) when SystemId /= undefined ->
    {error, "'system_id' in outbind has wrong type", SystemId};
check_outbind_system_id(_) ->
    {error, "'system_id' in outbind is no set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check field 'password' in outbind
%% @end
%%--------------------------------------------------------------------

-spec check_outbind_password(Outbind) -> Error when
      Outbind :: #outbind_field{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_outbind_password(#outbind_field{password = Password}) when is_list(Password) -> 
    [];
check_outbind_password(#outbind_field{password = Password}) when Password /= undefined ->
    {error, "'password' in outbind has wrong type", Password};
check_outbind_password(_) ->
    {error, "'password' in outbind is no set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check field 'host' in outbind
%% @end
%%--------------------------------------------------------------------

-spec check_outbind_host(Outbind) -> Error when
      Outbind :: #outbind_field{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_outbind_host(#outbind_field{host = Host}) when is_list(Host); Host == all -> 
    [];
check_outbind_host(#outbind_field{host = Host}) when Host /= undefined ->
    {error, "'host' in outbind has wrong type", Host};
check_outbind_host(_) ->
    {error, "'host' in outbind is no set"}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check field 'port' in outbind
%% @end
%%--------------------------------------------------------------------

-spec check_outbind_port(Outbind) -> Error when
      Outbind :: #outbind_field{},
      Error :: [] | {error, Message} | {error, Message, Value},
      Message :: string(),
      Value :: any().


check_outbind_port(#outbind_field{port = Port}) when is_number(Port), Port >= 0, Port =< 65535 ->
    [];
check_outbind_port(#outbind_field{port = Port}) when Port /= undefined ->
    {error, "'port' in outbind has wrong type or value", Port};
check_outbind_port(_) ->
    {error, "'port' in outbind is not set"}.

