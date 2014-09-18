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

-include("esmpp34.hrl").
-include("esmpp34_defs.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_constants.hrl").
-include_lib("esmpp34raw/include/esmpp34raw_types.hrl").


%% API
-export([
         cancel_timeout/2,
         reason2code/1,
         resolver/1,
	 proceed_data/3,
	 start_el_timer/1
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





proceed_data(_, #state{response_timers = Timers} = State, #pdu{sequence_number = Seq, body = #enquire_link_resp{}}) ->
    NewTimers = cancel_timeout(Seq, Timers),
    io:format("Received enquire_link_resp~n"),
    start_el_timer(State#state{response_timers = NewTimers});

proceed_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq,
						      body = #enquire_link{}}) ->
    %% TODO: cancel enquire_link timer
    io:format("Received enquire_link_req~n"),
    Resp = #enquire_link_resp{},
    Code = ?ESME_ROK,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    start_el_timer(State);

   

proceed_data(trx, #state{} = State, #pdu{} = Pdu) ->
    proceed_trx(State, Pdu);
proceed_data(tx, #state{} = State, #pdu{} = Pdu) ->
    proceed_tx(State, Pdu);
proceed_data(rx, #state{} = State, #pdu{} = Pdu) ->
    proceed_rx(State, Pdu).







proceed_trx(#state{} = State, #pdu{}) ->
    State.


proceed_tx(#state{} = State, #pdu{}) ->
    State.


proceed_rx(#state{} = State, #pdu{}) ->
    State.




start_el_timer(#state{el_timer = Timer, connection = #smpp_entity{el_interval = Interval}} = State) when Timer /= undefined->
    erlang:cancel_timer(Timer),
    NewTimer = erlang:send_after(Interval, self(), enquire_link),
    State#state{el_timer = NewTimer};

start_el_timer(#state{connection = #smpp_entity{el_interval = Interval}} = State) ->
    Timer = erlang:send_after(Interval, self(), enquire_link),
    State#state{el_timer = Timer}.


