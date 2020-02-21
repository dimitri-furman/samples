-- Create database master key. This is needed to encrypt data source credentials.
IF NOT EXISTS (
              SELECT 1
              FROM sys.symmetric_keys
              WHERE name = '##MS_DatabaseMasterKey##'
              )
    CREATE MASTER KEY;
GO

-- Create a separate schema for telemetry objects.
CREATE SCHEMA telemetry AUTHORIZATION dbo;
GO

-- Create a table for sys.dm_db_resource_stats data
-- IGNORE_DUP_KEY is used to avoid PK constraint violations when existing rows from sys.dm_db_resource_stats are inserted into the table.
-- This happens because on each execution of telemetry.spLoadResourceStatsBatchOnReadOnly, we are loading all 256 rows from sys.dm_db_resource_stats.
-- This is done for simplicity, to avoid persisting and managing high watermark timestamp.
CREATE TABLE telemetry.dm_db_resource_stats
(
end_time datetime NOT NULL,
avg_cpu_percent decimal(5,2) NULL,
avg_data_io_percent decimal(5,2) NULL,
avg_log_write_percent decimal(5,2) NULL,
avg_memory_usage_percent decimal(5,2) NULL,
xtp_storage_percent decimal(5,2) NULL,
max_worker_percent decimal(5,2) NULL,
max_session_percent decimal(5,2) NULL,
dtu_limit int NULL,
avg_login_rate_percent decimal(5,2) NULL,
avg_instance_cpu_percent decimal(5,2) NULL,
avg_instance_memory_percent decimal(5,2) NULL,
cpu_limit decimal(5,2) NULL,
replica_role int NULL,
replica_id uniqueidentifier NOT NULL
CONSTRAINT pk_telemetry_dm_db_resource_stats PRIMARY KEY (end_time) WITH (IGNORE_DUP_KEY = ON, DATA_COMPRESSION = ROW)
);

-- Create a table for snapshots of sys.dm_database_replica_states
CREATE TABLE telemetry.dm_database_replica_states
(
snapshot_time datetime NOT NULL,
database_id int NOT NULL,
replica_id uniqueidentifier NOT NULL,
group_database_id uniqueidentifier NOT NULL,
is_primary_replica bit NULL,
synchronization_state_desc nvarchar(120) NULL,
is_commit_participant bit NULL,
synchronization_health_desc nvarchar(120) NULL,
database_state_desc nvarchar(120) NULL,
is_suspended bit NULL,
suspend_reason_desc nvarchar(120) NULL,
last_received_time datetime NULL,
last_hardened_time datetime NULL,
last_redone_time datetime NULL,
log_send_queue_size bigint NULL,
log_send_rate bigint NULL,
redo_queue_size bigint NULL,
redo_rate bigint NULL,
last_commit_time datetime NULL,
secondary_lag_seconds bigint NULL,
CONSTRAINT pk_telemetry_dm_database_replica_states PRIMARY KEY (snapshot_time) WITH (DATA_COMPRESSION = ROW)
);

-- Create a database-scoped user that will be used to connect from the read-only replica to the read-write replica
CREATE USER TelemetryWriter WITH PASSWORD = 'replace-with-complex-password';

-- Grant minimum required permissions to this user
GRANT EXECUTE ON SCHEMA::telemetry TO TelemetryWriter;

-- Create a credential for this user, to be referenced in the data source 
CREATE DATABASE SCOPED CREDENTIAL TelemetryTargetCredential
WITH IDENTITY = 'TelemetryWriter',
     SECRET = 'replace-with-complex-password';

-- Create a data source, to be referenced in the sys.sp_execute_remote call
-- Change literal values for LOCATION and DATABASE_NAME to reflect the database to be monitored
CREATE EXTERNAL DATA SOURCE TelemetryTargetDataSource
WITH   
(
TYPE = RDBMS,   
LOCATION = 'server-name.database.windows.net', -- fully-qualified name of the logical server hosting the database to be monitored, e.g example-server.database.windows.net
DATABASE_NAME = 'database-name', -- name of the database to be monitored
CREDENTIAL = TelemetryTargetCredential
);
GO

-- For Hyperscale, keep global temp tables used for tagging replicas around for the lifetime of a replica
IF DATABASEPROPERTYEX(DB_NAME(), 'Edition') = 'Hyperscale'
    ALTER DATABASE SCOPED CONFIGURATION SET GLOBAL_TEMPORARY_TABLE_AUTO_DROP = OFF;
GO

-- Create a stored procedure to assign a replica_id to each Hyperscale replica
CREATE OR ALTER PROCEDURE telemetry.spAssignHyperscaleReplicaId
AS

SET XACT_ABORT, NOCOUNT ON;

/*
Hyperscale databases can have more than one read-scale secondary replica. 
Hyperscale replicas do not have a built-in replica identifier to associate with telemetry data from each replica.
Assign one here, by recording it in tempdb on a replica the first time this procedure executes on the replica.
This identifier persists for the uptime of the replica and will change over time as each replica is restarted.
However, it is sufficiently stable for many real-time troubleshooting and monitoring scenarios.
*/
IF OBJECT_ID('tempdb..##hs_replica') IS NULL
    CREATE TABLE ##hs_replica
    (
    one_row_lock bit NOT NULL CONSTRAINT ck_hs_replica_one_row_lock CHECK (one_row_lock = 1) CONSTRAINT df_hs_replica_one_row_lock DEFAULT (1),
    replica_id uniqueidentifier NOT NULL CONSTRAINT df_hs_replica_replica_id DEFAULT (NEWID())
    CONSTRAINT pk_hs_replica PRIMARY KEY (one_row_lock)
    );

IF NOT EXISTS (
              SELECT 1
              FROM ##hs_replica
              )
    INSERT INTO ##hs_replica
    DEFAULT VALUES;
GO

-- Create a stored procedure to load resource stats on the read-write primary
-- This procedure will be executed using sys.sp_execute_remote call on the read-only secondary
CREATE OR ALTER PROCEDURE telemetry.spLoadResourceStatsOnReadWrite
    @ResourceStatsJson nvarchar(max)
AS

SET XACT_ABORT, NOCOUNT ON;

-- Insert a batch of telemetry data passed in the JSON parameter
INSERT INTO telemetry.dm_db_resource_stats
(
end_time,
avg_cpu_percent,
avg_data_io_percent,
avg_log_write_percent,
avg_memory_usage_percent,
xtp_storage_percent,
max_worker_percent,
max_session_percent,
dtu_limit,
avg_login_rate_percent,
avg_instance_cpu_percent,
avg_instance_memory_percent,
cpu_limit,
replica_role,
replica_id
)
SELECT  end_time,
        avg_cpu_percent,
        avg_data_io_percent,
        avg_log_write_percent,
        avg_memory_usage_percent,
        xtp_storage_percent,
        max_worker_percent,
        max_session_percent,
        dtu_limit,
        avg_login_rate_percent,
        avg_instance_cpu_percent,
        avg_instance_memory_percent,
        cpu_limit,
        replica_role,
        replica_id
FROM OPENJSON(@ResourceStatsJson)
WITH (
     end_time datetime '$.end_time',
     avg_cpu_percent decimal '$.avg_cpu_percent',
     avg_data_io_percent decimal '$.avg_data_io_percent',
     avg_log_write_percent decimal '$.avg_log_write_percent',
     avg_memory_usage_percent decimal '$.avg_memory_usage_percent',
     xtp_storage_percent decimal '$.xtp_storage_percent',
     max_worker_percent decimal '$.max_worker_percent',
     max_session_percent decimal '$.max_session_percent',
     dtu_limit int '$.dtu_limit',
     avg_login_rate_percent decimal '$.avg_login_rate_percent',
     avg_instance_cpu_percent decimal '$.avg_instance_cpu_percent',
     avg_instance_memory_percent decimal '$.avg_instance_memory_percent',
     cpu_limit decimal '$.cpu_limit',
     replica_role int '$.replica_role',
     replica_id uniqueidentifier '$.replica_id'
     );
GO

-- Create a stored procedure to be periodically executed on the read-only secondary.
-- For sys.dm_db_resource_stats, this procedure should be executed at least once an hour to avoid gaps in resource stats data.
-- It can be executed more frequently to reduce data latency.
CREATE OR ALTER PROCEDURE telemetry.spLoadResourceStatsOnReadOnly
    @ReplicaID uniqueidentifier = NULL OUTPUT
AS
DECLARE @ResourceStatsJson nvarchar(max); 

SET XACT_ABORT, NOCOUNT ON;

-- Hyperscale, 0 to 4 read-scale replicas
IF EXISTS (
          SELECT 1
          FROM sys.database_service_objectives
          WHERE edition = 'Hyperscale'
          )
BEGIN
    -- Tag the replica with replica_id
    EXEC telemetry.spAssignHyperscaleReplicaId;

    -- Return replica_id
    SELECT @ReplicaID = replica_id
    FROM ##hs_replica;

    -- Get current snapshot of resource stats into a JSON document
    WITH rs AS
    (
    SELECT  drs.end_time,
            drs.avg_cpu_percent,
            drs.avg_data_io_percent,
            drs.avg_log_write_percent,
            drs.avg_memory_usage_percent,
            drs.xtp_storage_percent,
            drs.max_worker_percent,
            drs.max_session_percent,
            drs.dtu_limit,
            drs.avg_login_rate_percent,
            drs.avg_instance_cpu_percent,
            drs.avg_instance_memory_percent,
            drs.cpu_limit,
            drs.replica_role,
            hr.replica_id -- include replica identifier to distinguish among multiple Hyperscale replicas
    FROM sys.dm_db_resource_stats AS drs
    CROSS JOIN ##hs_replica AS hr
    )
    SELECT @ResourceStatsJson = (
                                SELECT *
                                FROM rs
                                FOR JSON AUTO, INCLUDE_NULL_VALUES
                                );
END
ELSE -- Premium or Business Critical, at most one read-scale replica
BEGIN
    -- Return ReplicaID
    SELECT TOP (1) @ReplicaID = dbrs.replica_id
    FROM sys.dm_database_replica_states AS dbrs
    WHERE database_id = DB_ID() -- in elastic pools, get the current database only
            AND
            is_local = 1; -- get data only for the secondary read-only replica we are connected to

    -- Get current snapshot of resource stats into a JSON document
    WITH rs AS
    (
    SELECT  drs.end_time,
            drs.avg_cpu_percent,
            drs.avg_data_io_percent,
            drs.avg_log_write_percent,
            drs.avg_memory_usage_percent,
            drs.xtp_storage_percent,
            drs.max_worker_percent,
            drs.max_session_percent,
            drs.dtu_limit,
            drs.avg_login_rate_percent,
            drs.avg_instance_cpu_percent,
            drs.avg_instance_memory_percent,
            drs.cpu_limit,
            drs.replica_role,
            @ReplicaID AS replica_id -- include replica identifier to detect when the secondary replica moves to a different node
    FROM sys.dm_db_resource_stats AS drs
    )
    SELECT @ResourceStatsJson = (
                                SELECT *
                                FROM rs
                                FOR JSON AUTO, INCLUDE_NULL_VALUES
                                );
END;

-- Pass JSON document as a parameter to the stored procedure on the read-write replica.
-- This loads resource stats into the telemetry.dm_db_resource_stats table.
EXEC sys.sp_execute_remote
    @data_source_name = N'TelemetryTargetDataSource',  
    @stmt = N'EXEC telemetry.spLoadResourceStatsOnReadWrite @ResourceStatsJson = @ResourceStatsJson',
    @params = N'@ResourceStatsJson nvarchar(max)',
    @ResourceStatsJson = @ResourceStatsJson;
GO

-- Create a stored procedure to load database replica state data on the read-write primary
-- This procedure will be executed using sys.sp_execute_remote call on the read-only secondary
-- Not applicable to Hyperscale because sys.dm_database_replica_states is not applicable there.
CREATE OR ALTER PROCEDURE telemetry.spLoadDbReplicaStatesOnReadWrite
    @DbReplicaStatesJson nvarchar(max)
AS

SET XACT_ABORT, NOCOUNT ON;

-- Insert a batch of telemetry data passed in the JSON parameter
INSERT INTO telemetry.dm_database_replica_states
(
snapshot_time,
database_id,
replica_id,
group_database_id,
is_primary_replica,
synchronization_state_desc,
is_commit_participant,
synchronization_health_desc,
database_state_desc,
is_suspended,
suspend_reason_desc,
last_received_time,
last_hardened_time,
last_redone_time,
log_send_queue_size,
log_send_rate,
redo_queue_size,
redo_rate,
last_commit_time,
secondary_lag_seconds
)
SELECT  snapshot_time,
        database_id,
        replica_id,
        group_database_id,
        is_primary_replica,
        synchronization_state_desc,
        is_commit_participant,
        synchronization_health_desc,
        database_state_desc,
        is_suspended,
        suspend_reason_desc,
        last_received_time,
        last_hardened_time,
        last_redone_time,
        log_send_queue_size,
        log_send_rate,
        redo_queue_size,
        redo_rate,
        last_commit_time,
        secondary_lag_seconds
FROM OPENJSON(@DbReplicaStatesJson)
WITH (
     snapshot_time datetime '$.snapshot_time',
     database_id int '$.database_id',
     replica_id uniqueidentifier '$.replica_id',
     group_database_id uniqueidentifier '$.group_database_id',
     is_primary_replica bit '$.is_primary_replica',
     synchronization_state_desc nvarchar(120) '$.synchronization_state_desc',
     is_commit_participant bit '$.is_commit_participant',
     synchronization_health_desc nvarchar(120) '$.synchronization_health_desc',
     database_state_desc nvarchar(120) '$.database_state_desc',
     is_suspended bit '$.is_suspended',
     suspend_reason_desc nvarchar(120) '$.suspend_reason_desc',
     last_received_time datetime '$.last_received_time',
     last_hardened_time datetime '$.last_hardened_time',
     last_redone_time datetime '$.last_redone_time',
     log_send_queue_size bigint '$.log_send_queue_size',
     log_send_rate bigint '$.log_send_rate',
     redo_queue_size bigint '$.redo_queue_size',
     redo_rate bigint '$.redo_rate',
     last_commit_time datetime '$.last_commit_time',
     secondary_lag_seconds bigint '$.secondary_lag_seconds'
     );
GO

-- Create a stored procedure to be periodically executed on the read-only secondary.
-- For sys.dm_database_replica_states, this procedure should be executed as frequently as needed to get sufficiently granular data,
-- for example every 10 seconds, or less frequently during idle periods.
-- Not applicable to Hyperscale because sys.dm_database_replica_states is not applicable there.
CREATE OR ALTER PROCEDURE telemetry.spLoadDbReplicaStatesOnReadOnly
AS

SET XACT_ABORT, NOCOUNT ON;

-- Get current snapshot of db replica states into a JSON document
DECLARE @DbReplicaStatesJson nvarchar(max) = (
                                             SELECT GETUTCDATE() AS snapshot_time,
                                                    database_id,
                                                    replica_id,
                                                    group_database_id,
                                                    is_primary_replica,
                                                    synchronization_state_desc,
                                                    is_commit_participant,
                                                    synchronization_health_desc,
                                                    database_state_desc,
                                                    is_suspended,
                                                    suspend_reason_desc,
                                                    last_received_time,
                                                    last_hardened_time,
                                                    last_redone_time,
                                                    log_send_queue_size,
                                                    log_send_rate,
                                                    redo_queue_size,
                                                    redo_rate,
                                                    last_commit_time,
                                                    secondary_lag_seconds
                                             FROM sys.dm_database_replica_states
                                             WHERE database_id = DB_ID() -- in elastic pools, get the current database only
                                                   AND
                                                   is_local = 1 -- get data only for the secondary read-only replica we are connected to
                                             FOR JSON AUTO, INCLUDE_NULL_VALUES
                                             );

-- Pass JSON document as a parameter to the stored procedure on the read-write replica.
-- This loads db replica states into the telemetry.dm_database_replica_states table.
EXEC sys.sp_execute_remote
    @data_source_name = N'TelemetryTargetDataSource',  
    @stmt = N'EXEC telemetry.spLoadDbReplicaStatesOnReadWrite @DbReplicaStatesJson = @DbReplicaStatesJson',
    @params = N'@DbReplicaStatesJson nvarchar(max)',
    @DbReplicaStatesJson = @DbReplicaStatesJson;
GO
