--
-- PostgreSQL database dump
--

\restrict hYFIszCJlHdefq1ywOcXOPMhl7imvOssoZGnwafoMkDzBRd5laOpxlfzJsDX8tW

-- Dumped from database version 14.19
-- Dumped by pg_dump version 15.14 (Ubuntu 15.14-1.pgdg22.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: inventario_tecnico_stock; Type: TABLE DATA; Schema: public; Owner: ispuser
--

INSERT INTO public.inventario_tecnico_stock VALUES
	(1, 3, 2, 46),
	(1, 1, 999, -8),
	(6, 3, 0, 0);


--
-- Data for Name: materiales; Type: TABLE DATA; Schema: public; Owner: ispuser
--

INSERT INTO public.materiales VALUES
	(1, 'MAT-1', 'Material 1', 1000.00),
	(2, 'MAT-2', 'Material 2', 2000.00),
	(3, 'MAT-3', 'Material 3', 3000.00);


--
-- Data for Name: tecnicos; Type: TABLE DATA; Schema: public; Owner: ispuser
--

INSERT INTO public.tecnicos VALUES
	(1, 'Técnico 1'),
	(2, 'Técnico 2'),
	(3, 'Técnico 3'),
	(4, 'Técnico 4'),
	(5, 'Técnico 5'),
	(6, 'Técnico 6'),
	(7, 'Técnico 7'),
	(8, 'Técnico 8'),
	(9, 'Técnico 9'),
	(10, 'Técnico 10');


--
-- PostgreSQL database dump complete
--

\unrestrict hYFIszCJlHdefq1ywOcXOPMhl7imvOssoZGnwafoMkDzBRd5laOpxlfzJsDX8tW

