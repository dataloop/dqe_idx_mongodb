%%%-------------------------------------------------------------------
%% @doc dqe_idx_mongodb top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(dqe_idx_mongodb_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    {ok, { {one_for_all, 0, 1}, [mongo_spec()]} }.

%%====================================================================
%% Internal functions
%%====================================================================

mongo_spec () ->
    Name = mongo_connection_pool,
    {ok, PoolSize} = application:get_env(dqe_idx_mongodb, pool_size),
    {ok, PoolMax} = application:get_env(dqe_idx_mongodb, pool_max),
    PoolArgs = [{name, {local, Name}},
                {worker_module, dqe_idx_mongodb},
                {size, PoolSize},
                {max_overflow, PoolMax}],
    MongoArgs = mongo_args(),
    poolboy:child_spec(Name, PoolArgs, MongoArgs).

mongo_args () ->
    A1 = case application:get_env(dqe_idx_mongodb, server) of
             {ok, {Host, Port}} ->
                 [{host, Host}, {port, Port}];
             _ ->
                 []
         end,
    A2 = get_binary_arg(database, A1),
    A3 = get_binary_arg(login, A2),
    A4 = get_binary_arg(password, A3),
    case application:get_env(dqe_idx_mongodb, slave_ok) of
        {ok, true} ->
            [{r_mode, slave_ok} | A4];
        _ ->
            A4
    end.

get_binary_arg (Name, Proplist) ->
    case application:get_env(dqe_idx_mongodb, Name) of
        {ok, Value} ->
            BValue = list_to_binary(Value),
            [{Name, BValue} | Proplist];
        _ ->
            Proplist
    end.
