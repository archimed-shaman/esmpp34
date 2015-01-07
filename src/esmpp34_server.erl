%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% Server listener
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


-module(esmpp34_server).
-author("Alexander Morozov aka ~ArchimeD~").

-behaviour(gen_server).

-include("esmpp34.hrl").



%% API
-export([ start_link/3,
          ask_stop/1 ]).

%% gen_server callbacks
-export([ init/1,
          handle_call/3,
          handle_cast/2,
          handle_info/2,
          terminate/2,
          code_change/3 ]).



-define(SERVER, ?MODULE).
-define(ACCEPT_INTERVAL, 1000).
-define(ACCEPT_TIMEOUT, 100).



-record(state, {host, port, listener, connection, connection_id = 0, timer}).



%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Start the server
%% @end
%%--------------------------------------------------------------------

start_link(Host, Port, Entity) ->
    io:format("server started with args: [~p:~p] ~p~n", [Host, Port, Entity]),
    gen_server:start_link(?MODULE, [{host, Host}, {port, Port}, {connection, Entity}], []).



%%--------------------------------------------------------------------
%% @doc
%% Ask listener to stop
%% @end
%%--------------------------------------------------------------------


ask_stop(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, ask_stop).



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initialize the server
%% @end
%%--------------------------------------------------------------------

init(Args) ->
    Connection = proplists:get_value(connection, Args),
    Host = proplists:get_value(host, Args),
    Port = proplists:get_value(port, Args),
    erlang:send_after(1, self(), start),
    {ok, #state{host = Host, port = Port, connection = Connection}}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%% @end
%%--------------------------------------------------------------------


handle_call(ask_stop, _From, State) ->
    io:format("Terminating server~n"),
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%% @end
%%--------------------------------------------------------------------

handle_cast(_Msg, State) ->
    {noreply, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------

handle_info(start, #state{host = Host, port = Port} = State) ->
    io:format("Listening on ~p:~p~n", [Host,Port]),
    starter(State);

handle_info(accept_if_any, #state{timer = OldTimer,
                                  listener = Socket,
                                  connection_id = ConnectionId,
                                  connection = Connection} = State) ->
    erlang:cancel_timer(OldTimer),
    LastConnectionId = accept_if_any(Socket, ConnectionId, Connection),
    Timer = erlang:send_after(?ACCEPT_INTERVAL, self(), accept_if_any),
    {noreply, State#state{timer = Timer, connection_id = LastConnectionId}};

handle_info(_Info, State) ->
    {noreply, State}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
%%--------------------------------------------------------------------

terminate(_Reason, #state{listener = Socket}) when Socket /= undefined ->
    io:format("Terminating server~n"),
    gen_tcp:close(Socket),
    ok;

terminate(_Reason, _State) ->
    io:format("Terminating server~n"),
    ok.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%%===================================================================
%%% Internal functions
%%%===================================================================

starter(#state{host = all, port = Port} = State) ->
    io:format("Starting at all interfaces on port ~p~n", [Port]),
    Options = [binary, {packet, raw}, {active, false}, {reuseaddr, true}],
    case gen_tcp:listen(Port, Options) of
        {ok, Socket} ->
            Timer = erlang:send_after(?ACCEPT_INTERVAL, self(), accept_if_any),
            {noreply, State#state{timer = Timer, listener = Socket}};
        {error, Reason} ->
            io:format("TCP Listener error start: ~p~n", [Reason]),
            {stop, {tcp_error, Reason}, State}
    end;

%% Listen always for all interfaces. Not secure, but not so problematic in reloading.
starter (#state{host = _Address} = State) ->
    starter(State#state{host = all}).
    %% case esmpp34_utils:resolver(Address) of
    %%     {ok, IpAddress} ->
    %%         io:format("Starting at ~p:~p~n", [Address, Port]),
    %%         Options = [binary, {ip, IpAddress}, {packet, raw}, {active, false}, {reuseaddr, true}],
    %%         case gen_tcp:listen(Port, Options) of
    %%             {ok, Socket} ->
    %%                 Timer = erlang:send_after(?ACCEPT_INTERVAL, self(), accept_if_any),
    %%                 {ok, State#state{timer = Timer, listener = Socket}};
    %%             {error, Reason}->
    %%                 io:format("TCP Listener error start: ~p~n", [Reason]),
    %%                 {stop, {tcp_error, Reason}}
    %%         end;
    %%     Error ->
    %%         %% FIXME: maybe insecure
    %%         io:format("Unable determine interface: [~p], starting on all... ~n", [Error]),
    %%         starter({all, Port}, State)
    %% end.


accept_if_any(Socket, ConnectionId, Connection) ->
    case gen_tcp:accept(Socket, ?ACCEPT_TIMEOUT) of
        {ok, ClientSocket} ->
            {ok, Child} = esmpp34_acceptor_sup:start_acceptor(ConnectionId, Connection, ClientSocket),
            case  gen_tcp:controlling_process(ClientSocket, Child) of
                ok ->
                    accept_if_any(Socket, ConnectionId + 1, Connection);
                {error, Error} ->
                    io:format("!!!!! UNABLE SET CONTROLLING PROCESS ~p: ~p~n", [Child, Error]),
                    ok %% TODO: stop server
            end;
        {error, timeout} ->
            ConnectionId;
        {error, Reason} ->
            io:format("Error occured while accepting socket: ~p~n", [Reason]),
            ConnectionId
    end.
