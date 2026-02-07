-- Masques Payment Infrastructure
-- 001: Create Database
--
-- Separate database from 'otel' to keep payment/identity concerns isolated.

CREATE DATABASE IF NOT EXISTS masques;
