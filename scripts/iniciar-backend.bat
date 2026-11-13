@echo off
REM Inicia la API Spring Boot en http://localhost:8080
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.13.9-hotspot
cd /d "G:\misProyectos\GROUP JCK\backend"
call mvnw.cmd spring-boot:run
