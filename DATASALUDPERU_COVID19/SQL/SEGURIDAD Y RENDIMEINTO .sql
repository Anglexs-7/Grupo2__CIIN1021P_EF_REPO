

USE DataSaludPeru;
GO

-- ===========================================
-- 1. SEGURIDAD Y RENDIMIENTO 
-- ===========================================

IF DATABASE_PRINCIPAL_ID('rol_admin_salud') IS NULL
    EXEC('CREATE ROLE rol_admin_salud');

IF DATABASE_PRINCIPAL_ID('rol_analista_salud') IS NULL
    EXEC('CREATE ROLE rol_analista_salud');

IF DATABASE_PRINCIPAL_ID('rol_auditor_salud') IS NULL
    EXEC('CREATE ROLE rol_auditor_salud');
GO

-- ===========================================
-- 2. ASIGNAR PERMISOS
-- ===========================================

-- ADMINISTRADOR
GRANT SELECT, INSERT, UPDATE, DELETE
ON dbo.CasosPositivosCovid TO rol_admin_salud;

GRANT SELECT, INSERT, UPDATE, DELETE
ON dbo.CasosFallecidosCovid TO rol_admin_salud;

GRANT EXECUTE ON dbo.sp_CargarPositivosCovid
TO rol_admin_salud;

GRANT EXECUTE ON dbo.sp_CargarFallecidosCovid
TO rol_admin_salud;

GRANT EXECUTE ON dbo.sp_ValidarPositivosCovid
TO rol_admin_salud;

-- AUDITOR
GRANT SELECT ON dbo.LogAuditoriaCovid
TO rol_auditor_salud;
GO

-- ===========================================
-- 3. VISTA DE SEGURIDAD
-- ===========================================

CREATE OR ALTER VIEW dbo.vw_ResumenCovid
AS
WITH Positivos AS (
    SELECT
        u.Departamento,
        COUNT_BIG(*) AS TotalPositivos
    FROM dbo.CasosPositivosCovid p
    JOIN dbo.DimUbicacionCovid u
        ON p.IdUbicacion = u.IdUbicacion
    GROUP BY u.Departamento
),
Fallecidos AS (
    SELECT
        u.Departamento,
        COUNT_BIG(*) AS TotalFallecidos
    FROM dbo.CasosFallecidosCovid f
    JOIN dbo.DimUbicacionCovid u
        ON f.IdUbicacion = u.IdUbicacion
    GROUP BY u.Departamento
)
SELECT
    COALESCE(p.Departamento, f.Departamento)
        AS Departamento,
    ISNULL(p.TotalPositivos, 0)
        AS TotalPositivos,
    ISNULL(f.TotalFallecidos, 0)
        AS TotalFallecidos
FROM Positivos p
FULL OUTER JOIN Fallecidos f
    ON p.Departamento = f.Departamento;
GO

-- ===========================================
-- 4. RESTRINGIR ACCESO DEL ANALISTA
-- ===========================================

-- Retirar permisos directos previamente
-- otorgados sobre las tablas del modelo.

REVOKE SELECT ON dbo.CasosPositivosCovid
FROM rol_analista_salud;

REVOKE SELECT ON dbo.CasosFallecidosCovid
FROM rol_analista_salud;

REVOKE SELECT ON dbo.DimSexoCovid
FROM rol_analista_salud;

REVOKE SELECT ON dbo.DimUbicacionCovid
FROM rol_analista_salud;

-- Permitir únicamente la vista resumida
GRANT SELECT ON dbo.vw_ResumenCovid
TO rol_analista_salud;
GO

-- ===========================================
-- 5. CREAR USUARIOS DE PRUEBA
-- ===========================================

IF USER_ID('demo_analista') IS NULL
    CREATE USER demo_analista WITHOUT LOGIN;

IF USER_ID('demo_auditor') IS NULL
    CREATE USER demo_auditor WITHOUT LOGIN;
GO

IF IS_ROLEMEMBER('rol_analista_salud',
                 'demo_analista') = 0
    ALTER ROLE rol_analista_salud
    ADD MEMBER demo_analista;

IF IS_ROLEMEMBER('rol_auditor_salud',
                 'demo_auditor') = 0
    ALTER ROLE rol_auditor_salud
    ADD MEMBER demo_auditor;
GO

-- ===========================================
-- 6. PROBAR PERMISOS DEL ANALISTA
-- ===========================================

BEGIN TRY
    EXECUTE AS USER = 'demo_analista';

    SELECT
        USER_NAME() AS Usuario,
        HAS_PERMS_BY_NAME(
            'dbo.vw_ResumenCovid',
            'OBJECT', 'SELECT'
        ) AS PuedeVerResumen,
        HAS_PERMS_BY_NAME(
            'dbo.CasosPositivosCovid',
            'OBJECT', 'SELECT'
        ) AS PuedeVerTablaOriginal,
        HAS_PERMS_BY_NAME(
            'dbo.CasosPositivosCovid',
            'OBJECT', 'INSERT'
        ) AS PuedeInsertar;

    REVERT;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;
GO

-- ===========================================
-- 7. PROBAR PERMISOS DEL AUDITOR
-- ===========================================

BEGIN TRY
    EXECUTE AS USER = 'demo_auditor';

    SELECT
        USER_NAME() AS Usuario,
        HAS_PERMS_BY_NAME(
            'dbo.LogAuditoriaCovid',
            'OBJECT', 'SELECT'
        ) AS PuedeVerAuditoria,
        HAS_PERMS_BY_NAME(
            'dbo.CasosPositivosCovid',
            'OBJECT', 'INSERT'
        ) AS PuedeInsertar;

    REVERT;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;
GO

-- ===========================================
-- 8. COMPROBAR VISTA Y ROLES
-- ===========================================

SELECT * FROM dbo.vw_ResumenCovid;

SELECT
    name AS NombreRol,
    type_desc AS Tipo
FROM sys.database_principals
WHERE name IN (
    'rol_admin_salud',
    'rol_analista_salud',
    'rol_auditor_salud'
);
GO

USE DataSaludPeru;
GO

-- ÍNDICE PARA POSITIVOS
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_CasosPositivos_Ubicacion_Fecha'
    AND object_id =
        OBJECT_ID('dbo.CasosPositivosCovid')
)
BEGIN
    CREATE NONCLUSTERED INDEX
        IX_CasosPositivos_Ubicacion_Fecha
    ON dbo.CasosPositivosCovid(
        IdUbicacion, FechaResultado
    );
END;
GO

-- ÍNDICE PARA FALLECIDOS
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_CasosFallecidos_Ubicacion'
    AND object_id =
        OBJECT_ID('dbo.CasosFallecidosCovid')
)
BEGIN
    CREATE NONCLUSTERED INDEX
        IX_CasosFallecidos_Ubicacion
    ON dbo.CasosFallecidosCovid(
        IdUbicacion
    );
END;
GO

-- MOSTRAR ÍNDICES EXISTENTES
SELECT
    t.name AS Tabla,
    i.name AS NombreIndice,
    i.type_desc AS Tipo
FROM sys.indexes i
JOIN sys.tables t
    ON i.object_id = t.object_id
WHERE i.name IN (
    'IX_CasosPositivos_Ubicacion_Fecha',
    'IX_CasosFallecidos_Ubicacion'
);
GO

-- MEDIR CONSULTA
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT COUNT_BIG(*) AS Total
FROM dbo.CasosPositivosCovid
WHERE IdUbicacion = 1
  AND FechaResultado >= '2022-01-01'
  AND FechaResultado < '2023-01-01'
OPTION (RECOMPILE);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
SELECT
    SERVERPROPERTY('InstanceDefaultBackupPath')
        AS RutaBackup,
    SERVERPROPERTY('InstanceDefaultDataPath')
        AS RutaDatos,
    SERVERPROPERTY('InstanceDefaultLogPath')
        AS RutaLog;


USE master;
GO

-- ===========================================
-- 1. BACKUP COMPLETO
-- ===========================================

BACKUP DATABASE DataSaludPeru
TO DISK =
'C:\SQLBackups\DataSaludPeru_FULL.bak'
WITH
    INIT,
    CHECKSUM,
    STATS = 10;
GO

-- ===========================================
-- 2. BACKUP DIFERENCIAL
-- ===========================================

BACKUP DATABASE DataSaludPeru
TO DISK =
'C:\SQLBackups\DataSaludPeru_DIFF.bak'
WITH
    DIFFERENTIAL,
    INIT,
    CHECKSUM,
    STATS = 10;
GO

-- ===========================================
-- 3. VERIFICAR RESPALDOS
-- ===========================================

RESTORE VERIFYONLY
FROM DISK =
'C:\SQLBackups\DataSaludPeru_FULL.bak'
WITH CHECKSUM;
GO

RESTORE VERIFYONLY
FROM DISK =
'C:\SQLBackups\DataSaludPeru_DIFF.bak'
WITH CHECKSUM;
GO

-- ===========================================
-- 4. CONSULTAR NOMBRES LÓGICOS
-- ===========================================

RESTORE FILELISTONLY
FROM DISK =
'C:\SQLBackups\DataSaludPeru_FULL.bak';
GO

USE master;
GO

-- RESTAURAR UNA COPIA, NO LA BASE ORIGINAL

RESTORE DATABASE DataSaludPeru_Prueba
FROM DISK =
'C:\SQLBackups\DataSaludPeru_FULL.bak'
WITH
    MOVE 'NOMBRE_LOGICO_DATOS'
        TO 'C:\SQLData\DataSaludPeru_Prueba.mdf',
    MOVE 'NOMBRE_LOGICO_LOG'
        TO 'C:\SQLData\DataSaludPeru_Prueba_log.ldf',
    NORECOVERY,
    CHECKSUM,
    STATS = 10;
GO

-- APLICAR RESPALDO DIFERENCIAL
RESTORE DATABASE DataSaludPeru_Prueba
FROM DISK =
'C:\SQLBackups\DataSaludPeru_DIFF.bak'
WITH
    RECOVERY,
    CHECKSUM,
    STATS = 10;
GO

-- VERIFICACIÓN FINAL
SELECT name, state_desc
FROM sys.databases
WHERE name = 'DataSaludPeru_Prueba';
GO

SELECT
    COUNT_BIG(*) AS TotalPositivos
FROM DataSaludPeru_Prueba.dbo.positivos_covid_limpio;

SELECT
    COUNT_BIG(*) AS TotalFallecidos
FROM DataSaludPeru_Prueba.dbo.fallecidos_covid_limpio;
GO

