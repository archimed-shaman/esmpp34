%%%-------------------------------------------------------------------
%%% @author Alexander Morozov aka ~ArchimeD~
%%% @copyright 2014, Alexander Morozov
%%% @doc
%%% Record and type definitions
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


-ifndef(esmpp34_hrl).
-define(esmpp34_hrl, true).
-author("Alexander Morozov aka ~ArchimeD~").


-type host() :: {all, Port :: inet:port_number()}
              | {Host :: inet:ip_address(), Port :: inet:port_number()}.

-type bind_mode() :: transmitter
                   | receiver
                   | transceiver.



%% TODO: add inet:address_family() = inet | inet6
-record(connection, { type                     :: server | client, %% server, client
                      host                     :: host(),
                      ip_options               :: list(),
                      login                    :: string(),
                      password                 :: string(),
                      response_timeout = 10000 :: pos_integer(),
                      el_interval      = 60000 :: pos_integer()
                    }).



-record(section_direction, { id                         :: non_neg_integer(),
                             mode         = transceiver :: bind_mode(), %% receiver, transmitter, transceiver
                             load_sharing = false       :: boolean(),
                             connections  = []          :: [#connection{}]
                           })


.
-record(config, {directions = [#section_direction{}]}).



-endif.
