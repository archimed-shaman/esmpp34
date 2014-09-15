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

-type entity_type() :: esme
                     | smsc.

-type mode() :: tx
              | rx
              | trx.
-type modes() :: [mode()].


-record(outbind, { host      :: inet:ip_address() | all,
                   port      :: inet:port_number(),
                   system_id :: string(),
                   password  :: string() }).

-record(smpp_entity, { id                 :: non_neg_integer(),
                       type               :: entity_type(),
                       host               :: inet:ip_address() | all,
                       port               :: inet:port_number(),
                       system_id          :: string(),
                       password           :: string(),
                       allowed_modes = [] :: modes(),
                       outbind            :: #outbind{} }).
-endif.
