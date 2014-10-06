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
         run_timer/2,
         reason2code/1,
         resolver/1,
         send_data/4,
         send_data/5,
	 receive_data/3,
	 start_el_timer/1,
         do_recv/3
        ]).


%% ===================================================================
%% API functions
%% ===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Stop the response timer for specified request 
%% @end
%%--------------------------------------------------------------------

-spec cancel_timeout(Seq, Timers :: Dict1) -> NewTimer :: Dict2 when
      Seq :: non_neg_integer(),
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
%% Run timer for the specified request
%% @end
%%--------------------------------------------------------------------

-spec run_timer(Seq, Timers :: Dict1) -> NewTimers :: Dict2 when
      Seq :: non_neg_integer(),
      Dict1 :: dict:dict(Key, Value),
      Dict2 :: dict:dict(Key, Value).


run_timer(Seq, Timers) ->
    Timer = erlang:send_after(30000, self(), {timeout, Seq}), %% TODO: interval from config
    dict:store(Seq, Timer, Timers).



%%--------------------------------------------------------------------
%% @doc
%% Return the corresponding SMPP status code
%% @end
%%--------------------------------------------------------------------

-spec reason2code(Reason) -> Code when
      Reason :: ok | system_id | password | already_bound | invalid_bind_status | atom(),
      Code :: non_neg_integer().


reason2code(ok)                  -> ?ESME_ROK;
reason2code(system_id)           -> ?ESME_RINVSYSID;
reason2code(password)            -> ?ESME_RINVPASWD;
reason2code(already_bound)       -> ?ESME_RALYBND;
reason2code(invalid_bind_status) -> ?ESME_RINVBNDSTS;
reason2code(_)                   -> ?ESME_RUNKNOWNERR.



%%--------------------------------------------------------------------
%% @doc
%% Resolve the symbolic name (DNS, hostname, IPv4 or IPv6 address)
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
%% Handle common PDUs and transfer others to the appropriate
%% bind state handlers
%% @end
%%--------------------------------------------------------------------

-spec receive_data(Mode, State, Pdu) -> NewState when
      Mode :: tx | rx | trx,
      State :: #state{},
      Pdu :: #pdu{},
      NewState :: #state{}.


receive_data(_, #state{response_timers = Timers} = State, #pdu{sequence_number = Seq, body = #enquire_link_resp{}}) ->
    NewTimers = cancel_timeout(Seq, Timers),
    io:format("Received enquire_link_resp~n"),
    start_el_timer(State#state{response_timers = NewTimers});

receive_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #enquire_link{}}) ->
    %% TODO: cancel enquire_link timer
    io:format("Received enquire_link_req~n"),
    Resp = #enquire_link_resp{},
    Code = ?ESME_ROK,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    start_el_timer(State);

receive_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #unbind{}}) ->
    %% TODO: stop
    Resp = #unbind_resp{},
    Code = ?ESME_ROK,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    State;

receive_data(_, #state{} = State, #pdu{body = #unbind_resp{}}) ->
    %% TODO: stop
    State;

receive_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #bind_transmitter{}}) ->
    Resp = #bind_transmitter_resp{},
    Code = ?ESME_RALYBND,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    State;

receive_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #bind_receiver{}}) ->
    Resp = #bind_receiver_resp{},
    Code = ?ESME_RALYBND,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    State;

receive_data(_, #state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #bind_transceiver{}}) ->
    Resp = #bind_transceiver_resp{},
    Code = ?ESME_RALYBND,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Seq)),
    State;

receive_data(Mode, #state{response_timers = Timers,
                          dir_pid = {Pid, _},
                          socket = Socket} = State, #pdu{sequence_number = Seq, body = Body} = Pdu) ->
    IsAllowed = is_allowed(Mode, Body),
    case is_response(Body) of
        true when IsAllowed ->
            %% it is response and it is allowed in current mode; send it to direction
            NewTimers = cancel_timeout(Seq, Timers),
            gen_server:call(Pid, {receive_data, Pdu}), %% FIXME: handle data in direction
            State#state{response_timers = NewTimers};
        true ->
            %% it is a response, but it isn't allowed in current mode; do nothing
            State;
        false when IsAllowed ->
            %% it is a request and it is allowed; send it to direction
            gen_server:call(Pid, {receive_data, Pdu}), %% FIXME: handle data in direction
            State;
        _ ->
            %% all other cases, in fact - disallowed request; reject it
            reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
            State
    end.



%%--------------------------------------------------------------------
%% @doc
%% Handle common PDUs and transfer others to the appropriate
%% bind state handlers
%% @end
%%--------------------------------------------------------------------

-spec send_data(Mode, State1, Body, Sequence) -> State2 when
      Mode :: tx | rx | trx,
      State1 :: #state{},
      Body :: pdu_body(),
      Sequence :: non_neg_integer(),
      State2 :: #state{}.


send_data(Mode, #state{socket = Socket, response_timers = Timers} = State, Body, Sequence) ->
    IsResponse = is_response(Body),
    case is_allowed(Mode, Body) of
        true when IsResponse ->
            %% It is allowed response, just send
            send_smpp(Socket, Body, Sequence),
            {ok, State};
        true ->
            NewTimers = case send_smpp(Socket, Body, Sequence) of
                            ok ->
                                run_timer(Sequence, Timers);
                            _ ->
                                %% FIXME: unable send, maybe force disconnect?
                                Timers
                        end,
            {ok, State#state{response_timers = NewTimers}};
        _ ->
            io:format("disallowed~n"),
            {error, invalid_bind_status}
    end.



%%--------------------------------------------------------------------
%% @doc
%% Handle common PDUs and transfer others to the appropriate
%% bind state handlers
%% @end
%%--------------------------------------------------------------------

-spec send_data(Mode, State1, Body, Sequence, Status) -> State2 when
      Mode :: tx | rx | trx,
      State1 :: #state{},
      Body :: pdu_body(),
      Sequence :: non_neg_integer(),
      Status :: non_neg_integer(),
      State2 :: #state{}.


send_data(Mode, #state{socket = Socket, response_timers = Timers} = State, Body, Sequence, Status) ->
    IsResponse = is_response(Body),
    case is_allowed(Mode, Body) of
        true when IsResponse ->
            %% It is allowed response, just send
            send_smpp(Socket, Body, Sequence, Status),
            {ok, State};
        true ->
            NewTimers = case send_smpp(Socket, Body, Sequence, Status) of
                            ok ->
                                run_timer(Sequence, Timers);
                            _ ->
                                %% FIXME: unable send, maybe force disconnect?
                                Timers
                        end,
            {ok, State#state{response_timers = NewTimers}};
        _ ->
            {error, invalid_bind_status}
    end.



%%--------------------------------------------------------------------
%% @doc
%% (Re)start the enquire link interval timer
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
%% Check, if PDU is allowed in the specific mode
%% @end
%%--------------------------------------------------------------------

-spec is_allowed(Mode, Pdu) -> boolean() when
      Mode :: tx | rx | trx,
      Pdu :: #pdu{}.


is_allowed(tx, Pdu) ->
    is_allowed_tx(Pdu);
is_allowed(rx, Pdu) ->
    is_allowed_rx(Pdu);
is_allowed(trx, Pdu) ->
    is_allowed_trx(Pdu).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check, if PDU is allowed in transceiver mode
%% @end
%%--------------------------------------------------------------------

-spec is_allowed_trx(Pdu) -> boolean() when
      Pdu :: #pdu{}.


is_allowed_trx(#replace_sm{}) -> %% FIXME: wtf? should be available, maybe  documentation
    false;
is_allowed_trx(#replace_sm_resp{}) ->
    false;
is_allowed_trx(#bind_receiver{}) ->
    false;
is_allowed_trx(#bind_transmitter{}) ->
    false;
is_allowed_trx(#bind_transceiver{}) ->
    false;
is_allowed_trx(#bind_receiver_resp{}) ->
    false;
is_allowed_trx(#bind_transmitter_resp{}) ->
    false;
is_allowed_trx(#bind_transceiver_resp{}) ->
    false;
is_allowed_trx(_) ->
    true.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check, if PDU is allowed in transmitter mode
%% @end
%%--------------------------------------------------------------------

-spec is_allowed_tx(Pdu) -> boolean() when
      Pdu :: #pdu{}.


is_allowed_tx(#deliver_sm{}) ->
    false;
is_allowed_tx(#deliver_sm_resp{}) ->
    false;
is_allowed_tx(#alert_notification{}) ->
    false;
is_allowed_tx(#bind_receiver{}) ->
    false;
is_allowed_tx(#bind_transmitter{}) ->
    false;
is_allowed_tx(#bind_transceiver{}) ->
    false;
is_allowed_tx(#bind_receiver_resp{}) ->
    false;
is_allowed_tx(#bind_transmitter_resp{}) ->
    false;
is_allowed_tx(#bind_transceiver_resp{}) ->
    false;
is_allowed_tx(_) ->
    true.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Check, if PDU is allowed in receiver mode
%% @end
%%--------------------------------------------------------------------

-spec is_allowed_rx(Pdu) -> boolean() when
      Pdu :: #pdu{}.


is_allowed_rx(#submit_sm{}) ->
    false;
is_allowed_rx(#submit_sm_resp{}) ->
    false;
is_allowed_rx(#submit_multi{}) ->
    false;
is_allowed_rx(#submit_multi_resp{}) ->
    false;
is_allowed_rx(#query_sm{}) ->
    false;
is_allowed_rx(#query_sm_resp{}) ->
    false;
is_allowed_rx(#cancel_sm{}) ->
    false;
is_allowed_rx(#cancel_sm_resp{}) ->
    false;
is_allowed_rx(#replace_sm{}) ->
    false;
is_allowed_rx(#replace_sm_resp{}) ->
    false;
is_allowed_rx(#bind_receiver{}) ->
    false;
is_allowed_rx(#bind_transmitter{}) ->
    false;
is_allowed_rx(#bind_transceiver{}) ->
    false;
is_allowed_rx(#bind_receiver_resp{}) ->
    false;
is_allowed_rx(#bind_transmitter_resp{}) ->
    false;
is_allowed_rx(#bind_transceiver_resp{}) ->
    false;
is_allowed_rx(_) ->
    true.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Resolve the symbolic IPv4 address to inet:ip_address()
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
%% Resolve the symbolic IPv6 address to inet:ip_address()
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
%% Resolve the symbolic name to inet:ip_address()
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



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Determine, if the PDU is a response
%% @end
%%--------------------------------------------------------------------

-spec is_response(PDU) -> boolean() when
      PDU :: pdu_body().


is_response(#bind_receiver_resp{}) ->
    true;
is_response(#bind_transmitter_resp{}) ->
    true;
is_response(#bind_transceiver_resp{}) ->
    true;
is_response(#unbind_resp{}) ->
    true;
is_response(#submit_sm_resp{}) ->
    true;
is_response(#submit_multi_resp{}) ->
    true;
is_response(#data_sm_resp{}) ->
    true;
is_response(#deliver_sm_resp{}) ->
    true;
is_response(#query_sm_resp{}) ->
    true;
is_response(#cancel_sm_resp{}) ->
    true;
is_response(#replace_sm_resp{}) ->
    true;
is_response(#enquire_link_resp{}) ->
    true;
is_response(_) ->
    false.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Reject the specified packet with generic_nack
%% @end
%%--------------------------------------------------------------------

-spec reject_smpp(Socket, Sequence, Code) -> ok | {error, Reason} when
      Socket :: gen_tcp:socket(),
      Sequence :: non_neg_integer(),
      Code :: non_neg_integer(),
      Reason :: closed | inet:posix().


reject_smpp(Socket, Sequence, Code) ->
    Resp = #generic_nack{},
    Code = ?ESME_RINVBNDSTS,
    gen_tcp:send(Socket, esmpp34raw:pack_single(Resp, Code, Sequence)).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Send the SMPP PDU to socket. Status is ESME_ROK.
%% @end
%%--------------------------------------------------------------------

-spec send_smpp(Socket, Packet, Sequence) -> GenTcpResponse when
      Socket :: gen_tcp:socket(),
      Packet :: pdu_body(),
      Sequence :: non_neg_integer(),
      GenTcpResponse :: ok | {error, Reason},
      Reason :: closed | inet:posix().


send_smpp(Socket, Packet, Sequence) ->
    gen_tcp:send(Socket, esmpp34raw:pack_single(Packet, ?ESME_ROK, Sequence)).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Send the SMPP PDU with specified status to socket.
%% @end
%%--------------------------------------------------------------------

-spec send_smpp(Socket, Packet, Sequence, Status) -> GenTcpResponse when
      Socket :: gen_tcp:socket(),
      Packet :: pdu_body(),
      Sequence :: non_neg_integer(),
      Status :: non_neg_integer(),
      GenTcpResponse :: ok | {error, Reason},
      Reason :: closed | inet:posix().


send_smpp(Socket, Packet, Sequence, Status) ->
    gen_tcp:send(Socket, esmpp34raw:pack_single(Packet, Status, Sequence)).



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Receive data from socket in passive mode
%% @end
%%--------------------------------------------------------------------

-spec do_recv(Socket, Accumulator, Counter) -> RecvData when
      Socket :: gen_tcp:socket(),
      Accumulator :: [] | [binary()],
      Counter :: non_neg_integer(),
      RecvData :: [] | [binary()].


do_recv(Socket, Accumulator, Counter) when Counter > 0 ->
    %% io:format("do recv(~p, ~p, ~p)~n", [Socket, Accumulator, Counter]),
    case gen_tcp:recv(Socket, 65535, 10) of
        {ok, Data} ->
            do_recv(Socket, [Data | Accumulator], Counter - 1);
        {error, _} ->
            lists:reverse(Accumulator)
    end;

do_recv(_Socket, Accumulator, _Counter) ->
    lists:reverse(Accumulator).
