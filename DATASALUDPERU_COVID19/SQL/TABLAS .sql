USE DataSaludPeru;
GO
SET NOCOUNT ON;
GO

-- 1. Comprobar tablas fuente
IF OBJECT_ID(N'dbo.positivos_covid_limpio',N'U') IS NULL
    RAISERROR(N'No existe dbo.positivos_covid_limpio',16,1);
IF OBJECT_ID(N'dbo.fallecidos_covid_limpio',N'U') IS NULL
    RAISERROR(N'No existe dbo.fallecidos_covid_limpio',16,1);
GO

-- 2. Tablas del modelo. No se borran tablas existentes.
IF OBJECT_ID(N'dbo.DimUbicacionCovid',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.DimUbicacionCovid (
  IdUbicacion INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  Departamento NVARCHAR(150) NOT NULL,
  Provincia NVARCHAR(150) NOT NULL,
  Distrito NVARCHAR(150) NOT NULL,
  CONSTRAINT UQ_DimUbicacionCovid UNIQUE(Departamento,Provincia,Distrito)
 );
END;
GO
IF OBJECT_ID(N'dbo.DimSexoCovid',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.DimSexoCovid (
  IdSexo INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  Sexo NVARCHAR(40) NOT NULL UNIQUE
 );
END;
GO
USE DataSaludPeru;
GO

SELECT TOP (20)
    fecha_resultado,

    TRY_CONVERT(
        BIGINT,
        fecha_resultado
    ) AS FechaNumerica,

    TRY_CONVERT(
        DATE,
        CONVERT(
            VARCHAR(20),
            TRY_CONVERT(BIGINT, fecha_resultado)
        ),
        112
    ) AS FechaConvertida

FROM dbo.positivos_covid_limpio;
IF OBJECT_ID(N'dbo.LogAuditoriaCovid',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.LogAuditoriaCovid (
  IdLog BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  Tabla NVARCHAR(128) NOT NULL,
  Operacion NVARCHAR(30) NOT NULL,
  IdRegistro BIGINT NULL,
  UsuarioSQL SYSNAME NOT NULL DEFAULT ORIGINAL_LOGIN(),
  Fecha DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  Detalle NVARCHAR(1000) NULL
 );
END;
GO
IF OBJECT_ID(N'dbo.CasosPositivosCovid',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.CasosPositivosCovid (
  IdCaso BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  IdPersonaFuente NVARCHAR(100) NULL,
  FechaCorte DATE NULL,
  FechaResultado DATE NULL,
  MetodoDx NVARCHAR(80) NULL,
  Edad INT NULL,
  UbigeoFuente NVARCHAR(20) NULL,
  IdSexo INT NOT NULL REFERENCES dbo.DimSexoCovid(IdSexo),
  IdUbicacion INT NOT NULL REFERENCES dbo.DimUbicacionCovid(IdUbicacion),
  FechaCarga DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT CK_CasosPositivos_Edad CHECK (Edad IS NULL OR Edad BETWEEN 0 AND 120)
 );
END;
GO
IF OBJECT_ID(N'dbo.CasosFallecidosCovid',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.CasosFallecidosCovid (
  IdFallecido BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  UUIDFuente NVARCHAR(100) NULL,
  Edad INT NULL,
  ClasificacionDef NVARCHAR(150) NULL,
  UbigeoFuente NVARCHAR(20) NULL,
  IdSexo INT NOT NULL REFERENCES dbo.DimSexoCovid(IdSexo),
  IdUbicacion INT NOT NULL REFERENCES dbo.DimUbicacionCovid(IdUbicacion),
  FechaFallecimiento DATE NULL,
  FechaCarga DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT CK_CasosFallecidos_Edad CHECK (Edad IS NULL OR Edad BETWEEN 0 AND 120)
 );
END;
GO
IF COL_LENGTH(N'dbo.CasosFallecidosCovid',N'FechaFallecimiento') IS NULL
    ALTER TABLE dbo.CasosFallecidosCovid ADD FechaFallecimiento DATE NULL;
GO

-- 3. Conversor: admite '20221208', '20221208.000000', '2022-12-08' y '08/12/2022'.
CREATE OR ALTER FUNCTION dbo.fn_FechaCovid(@Valor NVARCHAR(100))
RETURNS DATE
AS
BEGIN
 DECLARE @t NVARCHAR(100)=NULLIF(LTRIM(RTRIM(@Valor)),N'');
 DECLARE @d DATE;
 DECLARE @n DECIMAL(20,6);
 DECLARE @entero BIGINT;
 IF @t IS NULL RETURN NULL;
 SET @d=COALESCE(TRY_CONVERT(DATE,@t,112),TRY_CONVERT(DATE,@t,23),
                 TRY_CONVERT(DATE,@t,103),TRY_CONVERT(DATE,@t,120));
 IF @d IS NOT NULL RETURN @d;
 SET @n=TRY_CONVERT(DECIMAL(20,6),@t);
 IF @n IS NULL OR @n<>FLOOR(@n) RETURN NULL;
 SET @entero=TRY_CONVERT(BIGINT,@n);
 IF @entero BETWEEN 10000101 AND 99991231
     SET @d=TRY_CONVERT(DATE,CONVERT(VARCHAR(20),@entero),112);
 RETURN @d;
END;
GO
CREATE OR ALTER FUNCTION dbo.fn_GrupoEdadCovid(@Edad INT)
RETURNS NVARCHAR(30)
AS
BEGIN
 RETURN CASE WHEN @Edad IS NULL THEN N'Sin dato'
 WHEN @Edad NOT BETWEEN 0 AND 120 THEN N'No válida'
 WHEN @Edad<=17 THEN N'0-17' WHEN @Edad<=29 THEN N'18-29'
 WHEN @Edad<=59 THEN N'30-59' ELSE N'60+' END;
END;
GO

-- 4. Auditoría de positivos.
CREATE OR ALTER TRIGGER dbo.tr_AuditoriaPositivosCovid
ON dbo.CasosPositivosCovid AFTER INSERT,UPDATE,DELETE
AS
BEGIN
 SET NOCOUNT ON;
 INSERT INTO dbo.LogAuditoriaCovid(Tabla,Operacion,IdRegistro,Detalle)
 SELECT N'CasosPositivosCovid',CASE WHEN d.IdCaso IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
        i.IdCaso,N'Inserción o actualización'
 FROM inserted AS i LEFT JOIN deleted AS d ON d.IdCaso=i.IdCaso;
 INSERT INTO dbo.LogAuditoriaCovid(Tabla,Operacion,IdRegistro,Detalle)
 SELECT N'CasosPositivosCovid',N'DELETE',d.IdCaso,N'Eliminación'
 FROM deleted AS d LEFT JOIN inserted AS i ON i.IdCaso=d.IdCaso
 WHERE i.IdCaso IS NULL;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_IntegridadPositivosCovid
ON dbo.CasosPositivosCovid AFTER INSERT,UPDATE
AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted
           WHERE FechaResultado>FechaCorte AND FechaCorte IS NOT NULL)
 BEGIN
  RAISERROR(N'FechaResultado no puede ser posterior a FechaCorte.',16,1);
  ROLLBACK TRANSACTION;
  RETURN;
 END;
END;
GO

-- 5. Validar datos de la tabla FUENTE, no de la tabla destino.
CREATE OR ALTER PROCEDURE dbo.sp_ValidarPositivosCovid
AS
BEGIN
 SET NOCOUNT ON;
 SELECT COUNT_BIG(*) AS TotalFuente,
  SUM(CASE WHEN TRY_CONVERT(INT,p.edad) NOT BETWEEN 0 AND 120
                 OR p.edad IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END) AS EdadesInvalidas,
  SUM(CASE WHEN dbo.fn_FechaCovid(CONVERT(NVARCHAR(100),p.fecha_resultado)) IS NULL
           THEN CONVERT(BIGINT,1) ELSE 0 END) AS FechasResultadoInvalidas,
  SUM(CASE WHEN p.departamento IS NULL OR p.provincia IS NULL OR p.distrito IS NULL
           THEN CONVERT(BIGINT,1) ELSE 0 END) AS UbicacionesIncompletas
 FROM dbo.positivos_covid_limpio AS p;
END;
GO

-- 6. Carga de positivos. @Reemplazar=0 conserva los existentes y evita
--    reinsertar por combinación persona/fecha/método. No garantiza unicidad
--    cuando la fuente tiene duplicados idénticos: revisar antes de cargar.
CREATE OR ALTER PROCEDURE dbo.sp_CargarPositivosCovid @Reemplazar BIT=0
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF OBJECT_ID(N'dbo.positivos_covid_limpio',N'U') IS NULL
 BEGIN RAISERROR(N'Falta tabla de positivos.',16,1); RETURN; END;
 BEGIN TRY
  BEGIN TRANSACTION;
  IF @Reemplazar=1 DELETE FROM dbo.CasosPositivosCovid;

  INSERT INTO dbo.DimSexoCovid(Sexo)
  SELECT DISTINCT COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(40),p.sexo)))),N''),N'NO ESPECIFICADO')
  FROM dbo.positivos_covid_limpio AS p
  WHERE NOT EXISTS (
   SELECT 1 FROM dbo.DimSexoCovid AS s
   WHERE s.Sexo=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(40),p.sexo)))),N''),N'NO ESPECIFICADO'));

  ;WITH Ub AS (
   SELECT DISTINCT
    COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.departamento)))),N''),N'SIN DATO') AS D,
    COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.provincia)))),N''),N'SIN DATO') AS P,
    COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.distrito)))),N''),N'SIN DATO') AS T
   FROM dbo.positivos_covid_limpio AS p
  )
  INSERT INTO dbo.DimUbicacionCovid(Departamento,Provincia,Distrito)
  SELECT u.D,u.P,u.T FROM Ub AS u
  WHERE NOT EXISTS(SELECT 1 FROM dbo.DimUbicacionCovid AS x
                   WHERE x.Departamento=u.D AND x.Provincia=u.P AND x.Distrito=u.T);

  INSERT INTO dbo.CasosPositivosCovid
    (IdPersonaFuente,FechaCorte,FechaResultado,MetodoDx,Edad,UbigeoFuente,IdSexo,IdUbicacion)
  SELECT NULLIF(LTRIM(RTRIM(CONVERT(NVARCHAR(100),p.id_persona))),N''),
   f.FechaCorte,f.FechaResultado,
   LEFT(CONVERT(NVARCHAR(80),p.metododx),80),
   CASE WHEN TRY_CONVERT(INT,p.edad) BETWEEN 0 AND 120 THEN TRY_CONVERT(INT,p.edad) END,
   CONVERT(NVARCHAR(20),p.ubigeo),s.IdSexo,u.IdUbicacion
  FROM dbo.positivos_covid_limpio AS p
  CROSS APPLY (SELECT dbo.fn_FechaCovid(CONVERT(NVARCHAR(100),p.fecha_corte)) AS FechaCorte,
                      dbo.fn_FechaCovid(CONVERT(NVARCHAR(100),p.fecha_resultado)) AS FechaResultado) AS f
  INNER JOIN dbo.DimSexoCovid AS s
    ON s.Sexo=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(40),p.sexo)))),N''),N'NO ESPECIFICADO')
  INNER JOIN dbo.DimUbicacionCovid AS u
    ON u.Departamento=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.departamento)))),N''),N'SIN DATO')
   AND u.Provincia=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.provincia)))),N''),N'SIN DATO')
   AND u.Distrito=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.distrito)))),N''),N'SIN DATO')
  WHERE (f.FechaCorte IS NULL OR f.FechaResultado IS NULL OR f.FechaResultado<=f.FechaCorte)
    AND (@Reemplazar=1 OR NOT EXISTS (
      SELECT 1 FROM dbo.CasosPositivosCovid AS c
      WHERE ISNULL(c.IdPersonaFuente,N'')=ISNULL(NULLIF(LTRIM(RTRIM(CONVERT(NVARCHAR(100),p.id_persona))),N''),N'')
        AND (c.FechaResultado=f.FechaResultado OR (c.FechaResultado IS NULL AND f.FechaResultado IS NULL))
        AND ISNULL(c.MetodoDx,N'')=ISNULL(LEFT(CONVERT(NVARCHAR(80),p.metododx),80),N'')
    ));
  DECLARE @Insertados BIGINT=@@ROWCOUNT;
  COMMIT TRANSACTION;
  SELECT @Insertados AS RegistrosPositivosInsertados;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
  DECLARE @Error NVARCHAR(2048)=ERROR_MESSAGE();
  RAISERROR(N'Error al cargar positivos: %s',16,1,@Error);
 END CATCH;
END;
GO

-- 7. Carga de fallecidos. Las columnas observadas en la captura son
-- FECHA_CORTE, FECHA_FALLECIMIENTO, EDAD_DECLARADA, SEXO, CLASIFICACION_DEF,
-- DEPARTAMENTO, PROVINCIA y DISTRITO. UUID y UBIGEO se detectan si existen.
-- SQL dinámico evita errores de compilación si esas columnas son opcionales.
CREATE OR ALTER PROCEDURE dbo.sp_CargarFallecidosCovid @Reemplazar BIT=0
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF OBJECT_ID(N'dbo.fallecidos_covid_limpio',N'U') IS NULL
 BEGIN RAISERROR(N'Falta tabla de fallecidos.',16,1); RETURN; END;
 DECLARE @UUID NVARCHAR(200)=N'CAST(NULL AS NVARCHAR(100))';
 DECLARE @Ubigeo NVARCHAR(200)=N'CAST(NULL AS NVARCHAR(20))';
 IF COL_LENGTH(N'dbo.fallecidos_covid_limpio',N'UUID') IS NOT NULL
  SET @UUID=N'CONVERT(NVARCHAR(100),p.[UUID])';
 IF COL_LENGTH(N'dbo.fallecidos_covid_limpio',N'UBIGEO') IS NOT NULL
  SET @Ubigeo=N'CONVERT(NVARCHAR(20),p.[UBIGEO])';
 DECLARE @SQL NVARCHAR(MAX)=N'
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  IF @Reemplazar=1 DELETE FROM dbo.CasosFallecidosCovid;
  INSERT INTO dbo.DimSexoCovid(Sexo)
  SELECT DISTINCT COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(40),p.[SEXO])))),N''''),N''NO ESPECIFICADO'')
  FROM dbo.fallecidos_covid_limpio AS p
  WHERE NOT EXISTS(SELECT 1 FROM dbo.DimSexoCovid AS s
   WHERE s.Sexo=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(40),p.[SEXO])))),N''''),N''NO ESPECIFICADO''));
  ;WITH Ub AS (
   SELECT DISTINCT
    COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.[DEPARTAMENTO])))),N''''),N''SIN DATO'') AS D,
    COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.[PROVINCIA])))),N''''),N''SIN DATO'') AS P,
    COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.[DISTRITO])))),N''''),N''SIN DATO'') AS T
   FROM dbo.fallecidos_covid_limpio AS p
  )
  INSERT INTO dbo.DimUbicacionCovid(Departamento,Provincia,Distrito)
  SELECT u.D,u.P,u.T FROM Ub AS u
  WHERE NOT EXISTS(SELECT 1 FROM dbo.DimUbicacionCovid AS x
   WHERE x.Departamento=u.D AND x.Provincia=u.P AND x.Distrito=u.T);

  INSERT INTO dbo.CasosFallecidosCovid
   (UUIDFuente,Edad,ClasificacionDef,UbigeoFuente,IdSexo,IdUbicacion,FechaFallecimiento)
  SELECT '+@UUID+N',
   CASE WHEN TRY_CONVERT(INT,p.[EDAD_DECLARADA]) BETWEEN 0 AND 120 THEN TRY_CONVERT(INT,p.[EDAD_DECLARADA]) END,
   LEFT(CONVERT(NVARCHAR(150),p.[CLASIFICACION_DEF]),150),'+@Ubigeo+N',
   s.IdSexo,u.IdUbicacion,
   TRY_CONVERT(DATE,p.[FECHA_FALLECIMIENTO])
  FROM dbo.fallecidos_covid_limpio AS p
  INNER JOIN dbo.DimSexoCovid AS s
   ON s.Sexo=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(40),p.[SEXO])))),N''''),N''NO ESPECIFICADO'')
  INNER JOIN dbo.DimUbicacionCovid AS u
   ON u.Departamento=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.[DEPARTAMENTO])))),N''''),N''SIN DATO'')
  AND u.Provincia=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.[PROVINCIA])))),N''''),N''SIN DATO'')
  AND u.Distrito=COALESCE(NULLIF(UPPER(LTRIM(RTRIM(CONVERT(NVARCHAR(150),p.[DISTRITO])))),N''''),N''SIN DATO'')
  WHERE @Reemplazar=1 OR NOT EXISTS (
   SELECT 1 FROM dbo.CasosFallecidosCovid AS c
   WHERE ISNULL(c.UUIDFuente,N'''')=ISNULL('+@UUID+N',N'''')
     AND (c.FechaFallecimiento=TRY_CONVERT(DATE,p.[FECHA_FALLECIMIENTO])
       OR (c.FechaFallecimiento IS NULL AND p.[FECHA_FALLECIMIENTO] IS NULL))
     AND ISNULL(c.ClasificacionDef,N'''')=ISNULL(LEFT(CONVERT(NVARCHAR(150),p.[CLASIFICACION_DEF]),150),N'''')
  );
  DECLARE @Insertados BIGINT=@@ROWCOUNT;
  COMMIT TRANSACTION;
  SELECT @Insertados AS RegistrosFallecidosInsertados;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
  DECLARE @Error NVARCHAR(2048)=ERROR_MESSAGE();
  RAISERROR(N''Error al cargar fallecidos: %s'',16,1,@Error);
 END CATCH;';
 EXEC sys.sp_executesql @SQL,N'@Reemplazar BIT',@Reemplazar=@Reemplazar;
END;
GO

-- 8. Roles de acceso.

USE DataSaludPeru;
GO

-- 1. CREAR ROLES
IF DATABASE_PRINCIPAL_ID(N'rol_admin_salud') IS NULL
    EXEC(N'CREATE ROLE rol_admin_salud');

IF DATABASE_PRINCIPAL_ID(N'rol_analista_salud') IS NULL
    EXEC(N'CREATE ROLE rol_analista_salud');

IF DATABASE_PRINCIPAL_ID(N'rol_auditor_salud') IS NULL
    EXEC(N'CREATE ROLE rol_auditor_salud');
GO

-- 2. PERMISOS DEL ADMINISTRADOR
IF OBJECT_ID(N'dbo.CasosPositivosCovid', N'U') IS NOT NULL
    GRANT SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.CasosPositivosCovid TO rol_admin_salud;

IF OBJECT_ID(N'dbo.CasosFallecidosCovid', N'U') IS NOT NULL
    GRANT SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.CasosFallecidosCovid TO rol_admin_salud;

-- 3. PERMISOS PARA PROCEDIMIENTOS
IF OBJECT_ID(N'dbo.sp_CargarPositivosCovid', N'P') IS NOT NULL
    GRANT EXECUTE
    ON OBJECT::dbo.sp_CargarPositivosCovid TO rol_admin_salud;

IF OBJECT_ID(N'dbo.sp_CargarFallecidosCovid', N'P') IS NOT NULL
    GRANT EXECUTE
    ON OBJECT::dbo.sp_CargarFallecidosCovid TO rol_admin_salud;

IF OBJECT_ID(N'dbo.sp_ValidarPositivosCovid', N'P') IS NOT NULL
    GRANT EXECUTE
    ON OBJECT::dbo.sp_ValidarPositivosCovid TO rol_admin_salud;

-- 4. PERMISOS DEL ANALISTA
IF OBJECT_ID(N'dbo.DimUbicacionCovid', N'U') IS NOT NULL
    GRANT SELECT
    ON OBJECT::dbo.DimUbicacionCovid TO rol_analista_salud;

IF OBJECT_ID(N'dbo.DimSexoCovid', N'U') IS NOT NULL
    GRANT SELECT
    ON OBJECT::dbo.DimSexoCovid TO rol_analista_salud;

IF OBJECT_ID(N'dbo.CasosPositivosCovid', N'U') IS NOT NULL
    GRANT SELECT
    ON OBJECT::dbo.CasosPositivosCovid TO rol_analista_salud;

IF OBJECT_ID(N'dbo.CasosFallecidosCovid', N'U') IS NOT NULL
    GRANT SELECT
    ON OBJECT::dbo.CasosFallecidosCovid TO rol_analista_salud;

-- 5. PERMISOS DEL AUDITOR
IF OBJECT_ID(N'dbo.LogAuditoriaCovid', N'U') IS NOT NULL
    GRANT SELECT
    ON OBJECT::dbo.LogAuditoriaCovid TO rol_auditor_salud;
GO

-- 6. VERIFICAR ROLES
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

-- 9. Índices.
USE DataSaludPeru;
GO

-- ÍNDICE 1: CASOS POSITIVOS COVID
IF OBJECT_ID('dbo.CasosPositivosCovid', 'U') IS NOT NULL
AND COL_LENGTH('dbo.CasosPositivosCovid', 'IdUbicacion') IS NOT NULL
AND COL_LENGTH('dbo.CasosPositivosCovid', 'FechaResultado') IS NOT NULL
AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_CasosPositivos_Ubicacion_Fecha'
    AND object_id = OBJECT_ID('dbo.CasosPositivosCovid')
)
BEGIN
    EXEC('
        CREATE INDEX IX_CasosPositivos_Ubicacion_Fecha
        ON dbo.CasosPositivosCovid(IdUbicacion, FechaResultado)
    ');
END;
GO

-- ÍNDICE 2: CASOS FALLECIDOS COVID
IF OBJECT_ID('dbo.CasosFallecidosCovid', 'U') IS NOT NULL
AND COL_LENGTH('dbo.CasosFallecidosCovid', 'IdUbicacion') IS NOT NULL
AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_CasosFallecidos_Ubicacion'
    AND object_id = OBJECT_ID('dbo.CasosFallecidosCovid')
)
BEGIN
    EXEC('
        CREATE INDEX IX_CasosFallecidos_Ubicacion
        ON dbo.CasosFallecidosCovid(IdUbicacion)
    ');
END;
GO

-- VERIFICAR ÍNDICES CREADOS
SELECT
    t.name AS Tabla,
    i.name AS NombreIndice,
    i.type_desc AS TipoIndice
FROM sys.indexes i
INNER JOIN sys.tables t
    ON i.object_id = t.object_id
WHERE i.name IN (
    'IX_CasosPositivos_Ubicacion_Fecha',
    'IX_CasosFallecidos_Ubicacion'
);
GO
GO

-- 10. Verificación sin cargar millones de filas automáticamente.
SELECT dbo.fn_FechaCovid(N'20221208.000000') AS PruebaNumerica,
       dbo.fn_FechaCovid(N'2022-12-08') AS PruebaISO;
SELECT TOP(10) p.fecha_resultado,
       dbo.fn_FechaCovid(CONVERT(NVARCHAR(100),p.fecha_resultado)) AS FechaConvertida
FROM dbo.positivos_covid_limpio AS p;
EXEC dbo.sp_ValidarPositivosCovid;
SELECT N'positivos_covid_limpio' AS Tabla,COUNT_BIG(*) AS Total FROM dbo.positivos_covid_limpio
UNION ALL
SELECT N'fallecidos_covid_limpio',COUNT_BIG(*) FROM dbo.fallecidos_covid_limpio;
GO
USE DataSaludPeru
GO

IF OBJECT_ID('dbo.CasosUnificado', 'U') IS NULL
BEGIN 
 CREATE TABLE dbo.CasosUnificado(
IdRegistro BIGINT IDENTITY (1,1) PRIMARY KEY,
IdOrigen BIGINT NOT NULL,
TipoCaso NVARCHAR(20) NOT NULL,
Edad INT NULL,
Sexo NVARCHAR(40),
Departamento NVARCHAR(150),
Provincia NVARCHAR(150),
Distrito NVARCHAR(150),
FechaCaso Date NULL,
CONSTRAINT UQ_CasosUnificado
    UNIQUE (TipoCaso, IdOrigen)
 );
 END;
 GO
 ;WITH DatosUnificados AS 
 (
 Select 
  p.IdCaso AS IdOrigen,
  CAST('POSITIVO'AS NVARCHAR(20))AS TipoCaso,
  p.Edad,
  s.Sexo,
  u.Departamento,
  u.Provincia,
  u.Distrito,
  p.FechaResultado AS FechaCaso
FROM dbo.CasosPositivosCovid p 
INNER JOIN dbo.DimSexoCovid s
   ON p.IdSexo = s.IdSexo
INNER JOIN dbo.DImUbicacion 
UNION ALL
SELECT
        f.IdFallecido AS IdOrigen,
        CAST('FALLECIDO' AS NVARCHAR(20)) AS TipoCaso,
        f.Edad,
        s.Sexo,
        u.Departamento,
        u.Provincia,
        u.Distrito,
        f.FechaFallecimiento AS FechaCaso
    FROM dbo.CasosFallecidosCovid f
    INNER JOIN dbo.DimSexoCovid s
        ON f.IdSexo = s.IdSexo
    INNER JOIN dbo.DimUbicacionCovid u
        ON f.IdUbicacion = u.IdUbicacion
)

-- GUARDAR LOS REGISTROS EN LA TABLA UNIFICADA
INSERT INTO dbo.CasosUnificado
(
    IdOrigen,
    TipoCaso,
    Edad,
    Sexo,
    Departamento,
    Provincia,
    Distrito,
    FechaCaso
)
SELECT
    d.IdOrigen,
    d.TipoCaso,
    d.Edad,
    d.Sexo,
    d.Departamento,
    d.Provincia,
    d.Distrito,
    d.FechaCaso
FROM DatosUnificados d
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.CasosUnificado c
    WHERE c.IdOrigen = d.IdOrigen
      AND c.TipoCaso = d.TipoCaso
);
GO
-- MOSTRAR LOS PRIMEROS 100 REGISTROS
SELECT TOP 100 *
FROM dbo.CasosUnificado
ORDER BY IdRegistro;
 
 SELECT
    TipoCaso,
    COUNT(*) AS TotalCasos
FROM dbo.CasosUnificado
GROUP BY TipoCaso;