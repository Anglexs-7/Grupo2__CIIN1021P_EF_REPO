
-- =========================================
-- DATASALUDPERU - DATA WAREHOUSE
-- CREACIÓN DE BASE DE DATOS Y TABLAS
-- =========================================

USE master;
GO

-- 1. CREAR BASE DE DATOS
IF DB_ID('DataSaludPeru_DW') IS NULL
BEGIN
    CREATE DATABASE DataSaludPeru_DW;
END;
GO

USE DataSaludPeru_DW;
GO

-- =========================================
-- 2. DIMENSIÓN FECHA
-- =========================================

IF OBJECT_ID('dbo.DimFecha', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimFecha (
        IdFecha INT NOT NULL PRIMARY KEY,
        Fecha DATE NOT NULL,
        Anio INT,
        Mes INT,
        Dia INT
    );
END;
GO

-- =========================================
-- 3. DIMENSIÓN SEXO
-- =========================================

IF OBJECT_ID('dbo.DimSexo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimSexo (
        IdSexo INT NOT NULL PRIMARY KEY,
        Sexo NVARCHAR(40)
    );
END;
GO

-- =========================================
-- 4. DIMENSIÓN UBICACIÓN
-- =========================================

IF OBJECT_ID('dbo.DimUbicacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimUbicacion (
        IdUbicacion INT NOT NULL PRIMARY KEY,
        Departamento NVARCHAR(150),
        Provincia NVARCHAR(150),
        Distrito NVARCHAR(150)
    );
END;
GO

-- =========================================
-- 5. TABLA DE HECHOS
-- =========================================

IF OBJECT_ID('dbo.FactCasosCovid', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactCasosCovid (
        IdFact BIGINT IDENTITY(1,1) PRIMARY KEY,

        IdFecha INT NOT NULL,
        IdSexo INT NOT NULL,
        IdUbicacion INT NOT NULL,

        TipoCaso NVARCHAR(20),
        CantidadCasos BIGINT,

        CONSTRAINT FK_Fact_Fecha
            FOREIGN KEY (IdFecha)
            REFERENCES dbo.DimFecha(IdFecha),

        CONSTRAINT FK_Fact_Sexo
            FOREIGN KEY (IdSexo)
            REFERENCES dbo.DimSexo(IdSexo),

        CONSTRAINT FK_Fact_Ubicacion
            FOREIGN KEY (IdUbicacion)
            REFERENCES dbo.DimUbicacion(IdUbicacion)
    );
END;
GO

-- =========================================
-- 6. VERIFICAR TABLAS CREADAS
-- =========================================

SELECT
    TABLE_SCHEMA,
    TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
GO

-- =========================================
-- 7. CONTAR REGISTROS
-- =========================================

SELECT
    'DimFecha' AS Tabla,
    COUNT_BIG(*) AS Total
FROM dbo.DimFecha

UNION ALL

SELECT
    'DimSexo',
    COUNT_BIG(*)
FROM dbo.DimSexo

UNION ALL

SELECT
    'DimUbicacion',
    COUNT_BIG(*)
FROM dbo.DimUbicacion

UNION ALL

SELECT
    'FactCasosCovid',
    COUNT_BIG(*)
FROM dbo.FactCasosCovid;
GO
USE DataSaludPeru_DW;
GO

SELECT 'DimFecha' AS Tabla, COUNT(*) AS Total
FROM dbo.DimFecha
UNION ALL
SELECT 'DimSexo', COUNT(*)
FROM dbo.DimSexo
UNION ALL
SELECT 'DimUbicacion', COUNT(*)
FROM dbo.DimUbicacion
UNION ALL
SELECT 'FactCasosCovid', COUNT(*)
FROM dbo.FactCasosCovid;


