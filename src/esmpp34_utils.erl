%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% SMPP utilities
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

-module(esmpp34_utils).
-author("Alexander Morozov aka ~ArchimeD~").

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


%% ===================================================================
%% API functions
%% ===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Stops the response timer for specified request 
%% @end
%%--------------------------------------------------------------------

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



%%--------------------------------------------------------------------
%% @doc
%% Returns the corresponding SMPP status code
%% @end
%%--------------------------------------------------------------------

-spec reason2code(Reason) -> Code when
      Reason :: ok | system_id | password | already_bound | atom(),
      Code :: non_neg_integer().


reason2code(ok)            -> ?ESME_ROK;
reason2code(system_id)     -> ?ESME_RINVSYSID;
reason2code(password)      -> ?ESME_RINVPASWD;
reason2code(already_bound) -> ?ESME_RALYBND;
reason2code(_)             -> ?ESME_RUNKNOWNERR.



%%--------------------------------------------------------------------
%% @doc
%% Resolves the symbolic name (DNS, hostname, IPv4 or IPv6 address)
%% to inet:ip_address()
%% @end
%%--------------------------------------------------------------------

-spec resolver(Host) -> {ok, IP} | {error, Error} when
      Host :: string(),
      IP :: inet:ip_address(),
      Error :: any().


resolver(Host) ->
    %% FIXME: make as the list of funs, now dialyser will
    %% throw error here
    resolver_ipv4(Host).



%%--------------------------------------------------------------------
%% @doc
%% Handles common PDUs and transfer others to the appropriate
%% bind state handlers
%% @end
%%--------------------------------------------------------------------

-spec proceed_data(Mode, State, Pdu) -> NewState when
      Mode :: tx | rx | trx,
      State :: #state{},
      Pdu :: #pdu{},
      NewState :: #state{}.


proceed_data(_, #state{response_timers = Timers} = State, #pdu{sequence_number = Seq, body = #enquire_link_resp{}}) ->
    NewTimers = cancel_timeout(Seq, Timers),
    io:format("Received enquire_link_resp~n"),
    start_el_timer(State#state{response_timers = NewTimers});

proceed_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #enquire_link{}}) ->
    %% TODO: cancel enquire_link timer
    io:format("Received enquire_link_req~n"),
    Resp = #enquire_link_resp{},
    Code = ?ESME_ROK,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    start_el_timer(State);

proceed_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #unbind{}}) ->
    %% TODO: stop
    Resp = #unbind_resp{},
    Code = ?ESME_ROK,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    State;

proceed_data(_, #state{} = State, #pdu{body = #unbind_resp{}}) ->
    %% TODO: stop
    State;

proceed_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #bind_transmitter{}}) ->
    Resp = #bind_transmitter_resp{},
    Code = ?ESME_RALYBND,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    State;

proceed_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #bind_receiver{}}) ->
    Resp = #bind_receiver_resp{},
    Code = ?ESME_RALYBND,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    State;

proceed_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #bind_transceiver{}}) ->
    Resp = #bind_transceiver_resp{},
    Code = ?ESME_RALYBND,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    State;

proceed_data(trx, #state{} = State, #pdu{} = Pdu) ->
    proceed_trx(State, Pdu);

proceed_data(tx, #state{} = State, #pdu{} = Pdu) ->
    proceed_tx(State, Pdu);

proceed_data(rx, #state{} = State, #pdu{} = Pdu) ->
    proceed_rx(State, Pdu).



%%--------------------------------------------------------------------
%% @doc
%% (Re)starts the enquire link interval timer
%% @end
%%--------------------------------------------------------------------

-spec start_el_timer(State) -> NewState when
      State :: #state{},
      NewState :: #state{}.


start_el_timer(#state{el_timer = Timer, connection = #smpp_entity{el_interval = Interval}} = State) when Timer /= undefined->
    erlang:cancel_timer(Timer),
    NewTimer = erlang:send_after(Interval, self(), enquire_link),
    State#state{el_timer = NewTimer};

start_el_timer(#state{connection = #smpp_entity{el_interval = Interval}} = State) ->
    Timer = erlang:send_after(Interval, self(), enquire_link),
    State#state{el_timer = Timer}.



%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handles PDUs in transceiver mode
%% @end
%%--------------------------------------------------------------------

-spec proceed_trx(State, Pdu) -> NewState when
      State :: #state{},
      Pdu :: #pdu{},
      NewState :: #state{}.


proceed_trx(#state{dir_pid = Pid} = State, #pdu{} = Pdu) ->
    gen_server:call(Pid, Pdu), %% FIXME: handle data in direction
    State.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Rejects forbidden PDUs in transmitter mode and transfers others to
%% direction
%% @end
%%--------------------------------------------------------------------

-spec proceed_tx(State, Pdu) -> NewState when
      State :: #state{},
      Pdu :: #pdu{},
      NewState :: #state{}.


proceed_tx(#state{} = State, #pdu{}) ->
    State.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Rejects forbidden PDUs in receiver mode and transfers others to
%% direction
%% @end
%%--------------------------------------------------------------------

-spec proceed_rx(State, Pdu) -> NewState when
      State :: #state{},
      Pdu :: #pdu{},
      NewState :: #state{}.


proceed_rx(#state{} = State, #pdu{}) ->
    State.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Resolves the symbolic IPv4 address to inet:ip_address()
%% @end
%%--------------------------------------------------------------------

-spec resolver_ipv4(Host) -> {ok, IP} | {error, Error} when
      Host :: string(),
      IP :: inet:ip4_address(),
      Error :: any().


resolver_ipv4(Host) ->
    case inet:parse_ipv4_address(Host) of
        {ok, _} = Value -> Value;
        {error, _} -> resolver_ipv6(Host)
    end.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Resolves the symbolic IPv6 address to inet:ip_address()
%% @end
%%--------------------------------------------------------------------

-spec resolver_ipv6(Host) -> {ok, IP} | {error, Error} when
      Host :: string(),
      IP :: inet:ip6_address(),
      Error :: any().


resolver_ipv6(Host) ->
    case inet:parse_ipv6_address(Host) of
        {ok, _} = Value -> Value;
        {error, _} -> resolver_dns(Host)
    end.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Resolves the symbolic name to inet:ip_address()
%% @end
%%--------------------------------------------------------------------

-spec resolver_dns(Host) -> {ok, IP} | {error, Error} when
      Host :: string(),
      IP :: inet:ip_address(),
      Error :: any().


resolver_dns(Host) ->
    case inet_res:lookup(Host, any, a, [], 10000) of
        [IP | _] -> {ok, IP};
        [] -> {error, unable_resolve}
    end.


