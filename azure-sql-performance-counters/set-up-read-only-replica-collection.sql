/*
This helper script sets up a remote table to enable performance counter collection from a read-only database replica.

Replace placeholders with actual values and execute in the read-write database where collected data will be stored.

The "Allow Azure services and resources to access this server" option for the Azure SQL server hosting the monitored read-only replica must be enabled.
Alternatively, a database-level firewall rule allowing traffic from 0.0.0.0 must exist in the monitored read-only replica.
*/

IF NOT EXISTS (
              SELECT 1
              FROM sys.symmetric_keys
              WHERE name = '##MS_DatabaseMasterKey##'
              )
    CREATE MASTER KEY;

-- Login name and password to connect to the read-only database
CREATE DATABASE SCOPED CREDENTIAL PerfMonSourceCred
WITH IDENTITY = 'login-name-here',
SECRET = 'strong-password-here';

CREATE EXTERNAL DATA SOURCE PerfMonSource WITH
(
TYPE = RDBMS,   
LOCATION = 'source-server-name-here.database.windows.net', -- logical server hosting the read-only database
DATABASE_NAME = 'database-name-here', -- name of the read-only database  
CREDENTIAL = PerfMonSourceCred
);

CREATE EXTERNAL TABLE dbo.remote_dm_os_perf_counters
(
object_name nchar(128) COLLATE DATABASE_DEFAULT NOT NULL,
counter_name nchar(128) COLLATE DATABASE_DEFAULT NOT NULL,
instance_name nchar(128) COLLATE DATABASE_DEFAULT NULL,
cntr_value bigint NOT NULL,
cntr_type int NOT NULL
)  
WITH
(  
DATA_SOURCE = PerfMonSource,  
SCHEMA_NAME = 'sys',  
OBJECT_NAME = 'dm_os_performance_counters'  
);
