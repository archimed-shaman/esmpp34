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
         send_data/3,
         send_data/4,
	 receive_data/3,
	 start_el_timer/1
        ]).


%% ===================================================================
%% API functions
%% ===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Stop the response timer for specified request 
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
%% Return the corresponding SMPP status code
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

receive_data(trx, #state{response_timers = Timers} = State, #pdu{sequence_number = Seq, body = Body} = Pdu) ->
    NewTimers = case is_response(Body) of
                    true ->
                        cancel_timeout(Seq, Timers);
                    false ->
                        Timers
                end,
    receive_trx(State#state{response_timers = NewTimers}, Pdu);

receive_data(tx, #state{response_timers = Timers} = State, #pdu{sequence_number = Seq, body = Body} = Pdu) ->
    NewTimers = case is_response(Body) of
                    true ->
                        cancel_timeout(Seq, Timers);
                    false ->
                        Timers
                end,
    receive_tx(State#state{response_timers = NewTimers}, Pdu);

receive_data(rx, #state{response_timers = Timers} = State, #pdu{sequence_number = Seq, body = Body} = Pdu) ->
    NewTimers = case is_response(Body) of
                    true ->
                        cancel_timeout(Seq, Timers);
                    false ->
                        Timers
                end,
    receive_rx(State#state{response_timers = NewTimers}, Pdu).



%%--------------------------------------------------------------------
%% @doc
%% Handle common PDUs and transfer others to the appropriate
%% bind state handlers
%% @end
%%--------------------------------------------------------------------

-spec send_data(Mode, State1, Body) -> State2 when
      Mode :: tx | rx | trx,
      State1 :: #state{},
      Body :: pdu_body(),
      State2 :: #state{}.

                
send_data(tx, #state{} = State, Body) ->
    send_tx(State, Body, ?ESME_ROK);

send_data(rx, #state{} = State, Body) ->
    send_rx(State, Body, ?ESME_ROK);

send_data(trx, #state{} = State, Body) ->
    send_trx(State, Body, ?ESME_ROK).



%%--------------------------------------------------------------------
%% @doc
%% Handle common PDUs and transfer others to the appropriate
%% bind state handlers
%% @end
%%--------------------------------------------------------------------

-spec send_data(Mode, State1, Body, Status) -> State2 when
      Mode :: tx | rx | trx,
      State1 :: #state{},
      Body :: pdu_body(),
      Status :: non_neg_integer(),
      State2 :: #state{}.

                
send_data(tx, #state{} = State, Body, Status) ->
    send_tx(State, Body, Status);

send_data(rx, #state{} = State, Body, Status) ->
    send_rx(State, Body, Status);

send_data(trx, #state{} = State, Body, Status) ->
    send_trx(State, Body, Status).



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



send_tx(State, Body, Status) ->
    State.

send_rx(State, Body, Status) ->
    State.

send_trx(State, Body, Status) ->
    State.
    



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handle PDUs in transceiver mode
%% @end
%%--------------------------------------------------------------------

-spec receive_trx(State, Pdu) -> NewState when
      State :: #state{},
      Pdu :: #pdu{},
      NewState :: #state{}.


receive_trx(#state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #replace_sm{}}) ->
    reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
    State;

receive_trx(#state{} = State, #pdu{body = #replace_sm_resp{}}) ->
    %% it is not request, do nothing
    State;

receive_trx(#state{dir_pid = {Pid, _}} = State, #pdu{} = Pdu) ->
    gen_server:call(Pid, {receive_data, Pdu}), %% FIXME: handle data in direction
    State.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Reject forbidden PDUs in transmitter mode and transfers others to
%% direction
%% @end
%%--------------------------------------------------------------------

-spec receive_tx(State, Pdu) -> NewState when
      State :: #state{},
      Pdu :: #pdu{},
      NewState :: #state{}.


receive_tx(#state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #deliver_sm{}}) ->
    reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
    State;

receive_tx(#state{} = State, #pdu{body = #deliver_sm_resp{}}) ->
    %% it is not request, do nothing
    State;

receive_tx(#state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #alert_notification{}}) ->
    reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
    State;

receive_tx(#state{dir_pid = {Pid, _}} = State, #pdu{} = Pdu) ->
    gen_server:call(Pid, {receive_data, Pdu}),
    State.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Reject forbidden PDUs in receiver mode and transfers others to
%% direction
%% @end
%%--------------------------------------------------------------------

-spec receive_rx(State, Pdu) -> NewState when
      State :: #state{},
      Pdu :: #pdu{},
      NewState :: #state{}.


receive_rx(#state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #submit_sm{}}) ->
    reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
    State;

receive_rx(#state{} = State, #pdu{body = #submit_sm_resp{}}) ->
    %% it is not request, do nothing
    State;

receive_rx(#state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #submit_multi{}}) ->
    reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
    State;

receive_rx(#state{} = State, #pdu{body = #submit_multi_resp{}}) ->
    %% it is not request, do nothing
    State;

receive_rx(#state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #query_sm{}}) ->
    reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
    State;

receive_rx(#state{} = State, #pdu{body = #query_sm_resp{}}) ->
    %% it is not request, do nothing
    State;

receive_rx(#state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #cancel_sm{}}) ->
    reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
    State;

receive_rx(#state{} = State, #pdu{body = #cancel_sm_resp{}}) ->
    %% it is not request, do nothing
    State;

receive_rx(#state{socket = Socket} = State, #pdu{sequence_number = Seq, body = #replace_sm{}}) ->
    reject_smpp(Socket, Seq, ?ESME_RINVBNDSTS),
    State;

receive_rx(#state{} = State, #pdu{body = #replace_sm_resp{}}) ->
    %% it is not request, do nothing
    State;

receive_rx(#state{dir_pid = {Pid, _}} = State, #pdu{} = Pdu) ->
    gen_server:call(Pid, {receive_data, Pdu}),
    State.



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







