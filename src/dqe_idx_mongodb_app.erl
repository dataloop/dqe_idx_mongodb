%%%-------------------------------------------------------------------
%% @doc dqe_idx_mongodb public API
%% @end
%%%-------------------------------------------------------------------

-module(dqe_idx_mongodb_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    dqe_idx_mongodb_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
