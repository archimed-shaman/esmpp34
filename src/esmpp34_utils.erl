%%%-------------------------------------------------------------------
%%% @author morozov
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 17. Сент. 2014 18:03
%%%-------------------------------------------------------------------

-module(esmpp34_utils).
-author("morozov").

-include_lib("esmpp34raw/include/esmpp34raw_constants.hrl").

%% API
-export([
         cancel_timeout/2,
         reason2code/1,
         resolver/1
        ]).


-spec cancel_timeout(Seq :: non_neg_integer(), Timers :: Dict1) -> NewTimer :: Dict2 when
      Dict1 :: dict:dict(Key, Value),
      Dict2 :: dict:dict(Key, Value).

cancel_timeout(Seq, Timers) ->
    case dict:find(Seq, Timers) of
        {ok, Timer} ->
            erlang:cancel_timer(Timer),
            dict:erase(Seq, Timers);
        error ->
            Timers
    end.




-spec reason2code(Reason) -> Code when
      Reason :: atom(),
      Code :: non_neg_integer().

reason2code(system_id) ->
    ?ESME_RINVSYSID;
reason2code(password) ->
    ?ESME_RINVPASWD;
reason2code(already_bound) ->
    ?ESME_RALYBND;
reason2code(_) ->
    ?ESME_RUNKNOWNERR.



resolver(Host) ->
    resolver_ipv4(Host).

resolver_ipv4(Host) ->
    case inet:parse_ipv4_address(Host) of
        {ok, _} = Value -> Value;
        {error, _} -> resolver_ipv6(Host)
    end.

resolver_ipv6(Host) ->
    case inet:parse_ipv6_address(Host) of
        {ok, _} = Value -> Value;
        {error, _} -> resolver_dns(Host)
    end.

resolver_dns(Host) ->
    case inet_res:lookup(Host, any, a, [], 10000) of
        [IP | _] -> {ok, IP};
        [] -> {error, unable_resolve}
    end.
