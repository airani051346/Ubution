-- phpMyAdmin SQL Dump
-- version 5.2.2
-- https://www.phpmyadmin.net/
--
-- Host: mysql
-- Generation Time: Sep 16, 2025 at 06:55 AM
-- Server version: 8.4.6
-- PHP Version: 8.2.29

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `netvars`
--

-- --------------------------------------------------------

--
-- Table structure for table `hosts`
--

CREATE TABLE `hosts` (
  `Name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `HW-Type` varchar(40) COLLATE utf8mb4_unicode_ci NOT NULL,
  `template` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `mgmt_IPv4_addr` varchar(15) COLLATE utf8mb4_unicode_ci NOT NULL,
  `mgmt_IPv4_subnet` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `default-gwV4` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL,
  `mgmt_IPv6_addr` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `mgmt_IPv6_prefix` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `default-gwV6` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `otp` varchar(16) COLLATE utf8mb4_unicode_ci NOT NULL,
  `expertpw` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `member_of` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `hosts`
--

INSERT INTO `hosts` (`Name`, `HW-Type`, `template`, `mgmt_IPv4_addr`, `mgmt_IPv4_subnet`, `default-gwV4`, `mgmt_IPv6_addr`, `mgmt_IPv6_prefix`, `default-gwV6`, `otp`, `expertpw`, `member_of`) VALUES
('vpn-gw-1', '1595R Appliances', 'Feak-Spark', '10.1.0.10', '', '10.1.0.3', '2a04:6447:900:100::10', '', '2a04:6447:900:100::3', 'zubur1', 'zubur1', ''),
('vpn-gw-2', '1585R', 'Feak-Spark', '10.1.0.20', '', '10.1.0.3', '2a04:6447:900:100::20', '', '2a04:6447:900:100::3', 'zubur1', 'zubur1', ''),
('vpn-gw-3', '1585R', 'Feak-Spark', '10.1.0.30', '', '10.1.0.3', '2a04:6447:900:100::30', '', '2a04:6447:900:100::3', 'zubur1', 'zubur1', ''),
('vpn-gw-4', '1585R', 'Feak-Spark', '10.1.0.40', '', '10.1.0.3', '2a04:6447:900:100::40', '', '2a04:6447:900:100::3', 'zubur1', 'zubur1', ''),
('vpn-gw-5', '1585R', 'Feak-Spark', '10.1.0.50', '', '10.1.0.3', '2a04:6447:900:100::50', '', '2a04:6447:900:100::3', 'zubur1', 'zubur1', ''),
('cl2-gw1', '9000 Appliances', 'Full-GAIA-GW', '172.23.23.106', '', '172.23.23.4', '2a04:6447:900:500::21', '', '2a04:6447:900:500::4', 'zubur1', 'zubur1', 'cl2'),
('cl2-gw2', '9000 Appliances', 'Full-GAIA-GW', '172.23.23.107', '', '172.23.23.4', '2a04:6447:900:500::22', '', '2a04:6447:900:500::4', 'zubur1', 'zubur1', 'cl2'),
('cl2', '9000 Appliances', 'ClusterObject', '172.23.23.108', '', '172.23.23.4', '2a04:6447:900:500::23', '', '2a04:6447:900:500::4', 'zubur1', 'zubur1', 'cl2'),
('cl1-gw1', '9000 Appliances', 'Full-GAIA-GW', '172.23.23.175', '', '172.23.23.4', '2a04:6447:900:500::11', '', '2a04:6447:900:500::4', 'zubur1', 'zubur1', 'cl1'),
('cl1-gw2', '9000 Appliances', 'Full-GAIA-GW', '172.23.23.176', '', '172.23.23.4', '2a04:6447:900:500::12', '', '2a04:6447:900:500::4', 'zubur1', 'zubur1', 'cl1'),
('cl1', '9000 Appliances', 'ClusterObject', '172.23.23.177', '', '172.23.23.4', '2a04:6447:900:500::13', '', '2a04:6447:900:500::4', 'zubur1', 'zubur1', 'cl1');

-- --------------------------------------------------------

--
-- Table structure for table `host_interfaces`
--

CREATE TABLE `host_interfaces` (
  `id` int NOT NULL,
  `Name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Canonical key: e.g., Cl1, vpn-gw-1, mt-vpn-gw-6',
  `interface` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `vlan` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `ipv4_addr` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `IPv4_mask-len` varchar(2) COLLATE utf8mb4_unicode_ci NOT NULL,
  `ipv6_addr` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `prefix` varchar(2) COLLATE utf8mb4_unicode_ci NOT NULL,
  `topology` enum('INTERNAL','EXTERNAL') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `leads_to_dmz` tinyint(1) NOT NULL DEFAULT '0',
  `anti_spoof_action` enum('detect','prevent','off') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'detect',
  `Sync` tinyint(1) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `host_interfaces`
--

INSERT INTO `host_interfaces` (`id`, `Name`, `interface`, `vlan`, `ipv4_addr`, `IPv4_mask-len`, `ipv6_addr`, `prefix`, `topology`, `leads_to_dmz`, `anti_spoof_action`, `Sync`) VALUES
(1, 'cl1-gw1', 'eth1-01', '100', '10.1.0.1', '24', '2a04:6447:900:100::1', '64', 'EXTERNAL', 0, 'detect', 0),
(2, 'cl1-gw1', 'eth1-01', '101', '10.1.1.1', '24', '2a04:6447:900:101::1', '64', 'EXTERNAL', 0, 'detect', 0),
(3, 'cl1-gw1', 'eth1-01', '102', '10.1.2.1', '24', '2a04:6447:900:102::1', '64', 'EXTERNAL', 0, 'detect', 0),
(4, 'cl1-gw2', 'eth1-01', '100', '10.1.0.2', '24', '2a04:6447:900:100::2', '64', 'EXTERNAL', 0, 'detect', 0),
(5, 'cl1-gw2', 'eth1-01', '101', '10.1.1.2', '24', '2a04:6447:900:101::2', '64', 'EXTERNAL', 0, 'detect', 0),
(6, 'cl1-gw2', 'eth1-01', '102', '10.1.2.2', '24', '2a04:6447:900:102::2', '64', 'EXTERNAL', 0, 'detect', 0),
(7, 'cl1', 'eth1-01', '100', '10.1.0.3', '24', '2a04:6447:900:100::3', '64', 'EXTERNAL', 0, 'detect', 0),
(8, 'cl1', 'eth1-01', '101', '10.1.1.3', '24', '2a04:6447:900:101::3', '64', 'EXTERNAL', 0, 'detect', 0),
(9, 'cl1', 'eth1-01', '102', '10.1.2.3', '24', '2a04:6447:900:102::3', '64', 'EXTERNAL', 0, 'detect', 0),
(10, 'cl1-gw1', 'Sync', '', '192.168.20.1', '24', '', '', 'INTERNAL', 0, 'detect', 1),
(11, 'cl1-gw2', 'Sync', '', '192.168.20.2', '24', '', '', 'INTERNAL', 0, 'detect', 1),
(12, 'cl1-gw1', 'Mgmt', '', '172.23.23.175', '24', '2a04:6447:900:500::11', '64', 'INTERNAL', 0, 'detect', 0),
(13, 'cl1-gw2', 'Mgmt', '', '172.23.23.176', '24', '2a04:6447:900:501::12', '64', 'INTERNAL', 0, 'detect', 0),
(14, 'cl1', 'Mgmt', '', '172.23.23.177', '24', '2a04:6447:900:500::13', '64', 'INTERNAL', 0, 'detect', 0),
(15, 'cl1-gw1', 'eth1-02', '200', '10.2.0.1', '24', '2a04:6447:900:200::1', '64', 'EXTERNAL', 0, 'detect', 0),
(16, 'cl1-gw2', 'eth1-02', '200', '10.2.0.2', '24', '2a04:6447:900:200::2', '64', 'EXTERNAL', 0, 'detect', 0),
(17, 'cl1', 'eth1-02', '200', '10.2.0.3', '24', '2a04:6447:900:200::3', '64', 'EXTERNAL', 0, 'detect', 0),
(18, 'cl2-gw1', 'eth2-01', '300', '10.3.0.1', '24', '2a04:6447:900:300::1', '64', 'EXTERNAL', 0, 'detect', 0),
(19, 'cl2-gw2', 'eth2-01', '300', '10.3.0.2', '24', '2a04:6447:900:300::2', '64', 'EXTERNAL', 0, 'detect', 0),
(20, 'cl2', 'eth2-02', '300', '10.3.0.3', '24', '2a04:6447:900:300::3', '64', 'EXTERNAL', 0, 'detect', 0),
(21, 'cl2-gw1', 'eth2-02', '400', '10.4.0.1', '24', '2a04:6447:900:400::1', '64', 'INTERNAL', 0, 'detect', 0),
(22, 'cl2-gw2', 'eth2-02', '400', '10.4.0.2', '24', '2a04:6447:900:400::2', '64', 'INTERNAL', 0, 'detect', 0),
(23, 'cl2', 'eth2-02', '400', '10.4.0.3', '24', '2a04:6447:900:400::3', '64', 'INTERNAL', 0, 'detect', 0),
(24, 'cl2-gw1', 'eth5', '', '172.23.23.106', '24', '2a04:6447:900:500::21', '64', 'INTERNAL', 0, 'detect', 1),
(25, 'cl2-gw2', 'eth5', '', '172.23.23.107', '24', '2a04:6447:900:500::22', '64', 'INTERNAL', 0, 'detect', 1),
(26, 'cl2', 'eth5', '', '172.23.23.108', '24', '2a04:6447:900:500::23', '64', 'INTERNAL', 0, 'detect', 1),
(27, 'vpn-gw-1', 'WAN', '100', '10.1.0.10', '24', '2a04:6447:900:100::10', '64', 'EXTERNAL', 0, 'detect', 0),
(28, 'vpn-gw-2', 'WAN', '100', '10.1.0.20', '24', '2a04:6447:900:100::20', '64', 'EXTERNAL', 0, 'detect', 0),
(29, 'vpn-gw-3', 'WAN', '100', '10.1.0.30', '24', '2a04:6447:900:100::30', '64', 'EXTERNAL', 0, 'detect', 0),
(30, 'vpn-gw-4', 'WAN', '100', '10.1.0.40', '24', '2a04:6447:900:100::40', '64', 'EXTERNAL', 0, 'detect', 0),
(31, 'vpn-gw-5', 'WAN', '100', '10.1.0.50', '24', '2a04:6447:900:100::50', '64', 'EXTERNAL', 0, 'detect', 0),
(32, 'vpn-gw-1', 'WAN', '101', '10.1.1.10', '24', '2a04:6447:900:101::10', '64', 'EXTERNAL', 0, 'detect', 0),
(33, 'vpn-gw-2', 'WAN', '101', '10.1.1.20', '24', '2a04:6447:900:101::20', '64', 'EXTERNAL', 0, 'detect', 0),
(34, 'vpn-gw-3', 'WAN', '101', '10.1.1.30', '24', '2a04:6447:900:101::30', '64', 'EXTERNAL', 0, 'detect', 0),
(35, 'vpn-gw-4', 'WAN', '101', '10.1.1.40', '24', '2a04:6447:900:101::40', '64', 'EXTERNAL', 0, 'detect', 0),
(36, 'vpn-gw-5', 'WAN', '101', '10.1.1.50', '24', '2a04:6447:900:101::50', '64', 'EXTERNAL', 0, 'detect', 0),
(37, 'vpn-gw-1', 'WAN', '102', '10.1.2.10', '24', '2a04:6447:900:102::10', '64', 'EXTERNAL', 0, 'detect', 0),
(38, 'vpn-gw-2', 'WAN', '102', '10.1.2.20', '24', '2a04:6447:900:102::20', '64', 'EXTERNAL', 0, 'detect', 0),
(39, 'vpn-gw-3', 'WAN', '102', '10.1.2.30', '24', '2a04:6447:900:102::30', '64', 'EXTERNAL', 0, 'detect', 0),
(40, 'vpn-gw-4', 'WAN', '102', '10.1.2.40', '24', '2a04:6447:900:102::40', '64', 'EXTERNAL', 0, 'detect', 0),
(41, 'vpn-gw-5', 'WAN', '102', '10.1.2.50', '24', '2a04:6447:900:102::50', '64', 'EXTERNAL', 0, 'detect', 0),
(42, 'vpn-gw-1', 'LAN1', '', '10.11.0.1', '24', '2a04:6447:900:1100::1', '64', 'INTERNAL', 0, 'detect', 0),
(43, 'vpn-gw-2', 'LAN1', '', '10.21.0.1', '24', '2a04:6447:900:2100::1', '64', 'INTERNAL', 0, 'detect', 0),
(44, 'vpn-gw-3', 'LAN1', '', '10.31.0.1', '24', '2a04:6447:900:3100::1', '64', 'INTERNAL', 0, 'detect', 0),
(45, 'vpn-gw-4', 'LAN1', '', '10.41.0.1', '24', '2a04:6447:900:4100::1', '64', 'INTERNAL', 0, 'detect', 0),
(46, 'vpn-gw-5', 'LAN1', '', '10.51.0.1', '24', '2a04:6447:900:5100::1', '64', 'INTERNAL', 0, 'detect', 0),
(47, 'vpn-gw-1', 'LAN2', '', '10.11.1.1', '24', '2a04:6447:900:1101::1', '64', 'INTERNAL', 0, 'detect', 0),
(48, 'vpn-gw-2', 'LAN2', '', '10.21.1.1', '24', '2a04:6447:900:2101::1', '64', 'INTERNAL', 0, 'detect', 0),
(49, 'vpn-gw-3', 'LAN2', '', '10.31.1.1', '24', '2a04:6447:900:3101::1', '64', 'INTERNAL', 0, 'detect', 0),
(50, 'vpn-gw-4', 'LAN2', '', '10.41.1.40', '24', '2a04:6447:900:4101::1', '64', 'INTERNAL', 0, 'detect', 0),
(51, 'vpn-gw-5', 'LAN2', '', '10.51.1.1', '24', '2a04:6447:900:5101::1', '64', 'INTERNAL', 0, 'detect', 0),
(52, 'vpn-gw-1', 'LAN3', '', '10.11.2.1', '24', '2a04:6447:900:1102::1', '64', 'INTERNAL', 0, 'detect', 0),
(53, 'vpn-gw-2', 'LAN3', '', '10.21.2.1', '24', '2a04:6447:900:2102::1', '64', 'INTERNAL', 0, 'detect', 0),
(54, 'vpn-gw-3', 'LAN3', '', '10.31.2.1', '24', '2a04:6447:900:3102::1', '64', 'INTERNAL', 0, 'detect', 0),
(55, 'vpn-gw-4', 'LAN3', '', '10.41.2.40', '24', '2a04:6447:900:4102::1', '64', 'INTERNAL', 0, 'detect', 0),
(56, 'vpn-gw-5', 'LAN3', '', '10.51.2.1', '24', '2a04:6447:900:5102::1', '64', 'INTERNAL', 0, 'detect', 0),
(57, 'cl2-gw1', 'eth3', '', '192.168.20.2', '24', '', '', 'INTERNAL', 0, 'detect', 0),
(58, 'cl2-gw2', 'eth3', '', '192.168.20.3', '24', '', '', 'INTERNAL', 0, 'detect', 0),
(59, 'cl1', 'eth1-01', '100', '10.1.0.3', '24', '2a04:6447:900:100::3', '64', 'EXTERNAL', 0, 'detect', 0);

-- --------------------------------------------------------

--
-- Table structure for table `host_internet_spark`
--

CREATE TABLE `host_internet_spark` (
  `id` int NOT NULL,
  `Name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `interface` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `vlan` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `ipv4_addr` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `IPv4_mask-len` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `ipv4_defaultgw` varchar(25) COLLATE utf8mb4_unicode_ci NOT NULL,
  `ipv6_addr` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `prefix` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `ipv6_defaultgw` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `host_internet_spark`
--

INSERT INTO `host_internet_spark` (`id`, `Name`, `interface`, `vlan`, `ipv4_addr`, `IPv4_mask-len`, `ipv4_defaultgw`, `ipv6_addr`, `prefix`, `ipv6_defaultgw`) VALUES
(1, 'vpn-gw-1', 'WAN', '100', '10.1.0.10', '24', '10.1.0.3', '2a04:6447:900:100::10', '64', '2a04:6447:900:100::3'),
(2, 'vpn-gw-2', 'WAN', '100', '10.1.0.20', '24', '10.1.0.3', '2a04:6447:900:100::20', '64', '2a04:6447:900:100::3'),
(3, 'vpn-gw-3', 'WAN', '100', '10.1.0.30', '24', '10.1.0.3', '2a04:6447:900:100::30', '64', '2a04:6447:900:100::3'),
(4, 'vpn-gw-4', 'WAN', '100', '10.1.0.40', '24', '10.1.0.3', '2a04:6447:900:100::40', '64', '2a04:6447:900:100::3'),
(5, 'vpn-gw-5', 'WAN', '100', '10.1.0.50', '24', '10.1.0.3', '2a04:6447:900:100::50', '64', '2a04:6447:900:100::3'),
(6, 'vpn-gw-1', 'WAN', '101', '10.1.1.30', '24', '10.1.1.3', '2a04:6447:900:101::30', '64', '2a04:6447:900:101::3'),
(7, 'vpn-gw-2', 'WAN', '101', '10.1.1.30', '24', '10.1.1.3', '2a04:6447:900:101::30', '64', '2a04:6447:900:101::3'),
(8, 'vpn-gw-3', 'WAN', '101', '10.1.1.30', '24', '10.1.1.3', '2a04:6447:900:101::30', '64', '2a04:6447:900:101::3'),
(9, 'vpn-gw-4', 'WAN', '101', '10.1.1.40', '24', '10.1.1.3', '2a04:6447:900:101::40', '64', '2a04:6447:900:101::3'),
(10, 'vpn-gw-5', 'WAN', '101', '10.1.1.50', '24', '10.1.1.3', '2a04:6447:900:101::50', '64', '2a04:6447:900:101::3'),
(11, 'vpn-gw-1', 'WAN', '102', '10.1.2.30', '24', '10.1.2.3', '2a04:6447:900:102::30', '64', '2a04:6447:900:102::3'),
(12, 'vpn-gw-2', 'WAN', '102', '10.1.2.30', '24', '10.1.2.3', '2a04:6447:900:102::30', '64', '2a04:6447:900:102::3'),
(13, 'vpn-gw-3', 'WAN', '102', '10.1.2.30', '24', '10.1.2.3', '2a04:6447:900:102::30', '64', '2a04:6447:900:102::3'),
(14, 'vpn-gw-4', 'WAN', '102', '10.1.2.40', '24', '10.1.2.3', '2a04:6447:900:102::40', '64', '2a04:6447:900:102::3'),
(15, 'vpn-gw-5', 'WAN', '102', '10.1.2.50', '24', '10.1.2.3', '2a04:6447:900:102::50', '64', '2a04:6447:900:102::3');

-- --------------------------------------------------------

--
-- Table structure for table `host_routes`
--

CREATE TABLE `host_routes` (
  `id` int NOT NULL,
  `Name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `SourceV4` varchar(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `sourceV4_mask` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `destV4` varchar(25) COLLATE utf8mb4_unicode_ci NOT NULL,
  `destV4_mask` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nexthopV4` varchar(25) COLLATE utf8mb4_unicode_ci NOT NULL,
  `SourceV6` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `sourceV6_prefix` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `destV6` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `destV6_prefix` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nexthopV6` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `host_routes`
--

INSERT INTO `host_routes` (`id`, `Name`, `SourceV4`, `sourceV4_mask`, `destV4`, `destV4_mask`, `nexthopV4`, `SourceV6`, `sourceV6_prefix`, `destV6`, `destV6_prefix`, `nexthopV6`) VALUES
(10, 'vpn-gw-1', '10.11.0.0', '24', '10.2.0.0', '24', '10.1.0.3', '2a04:6447:900:1100::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:100::3'),
(11, 'vpn-gw-1', '10.11.1.0', '24', '10.2.0.0', '24', '10.1.1.3', '2a04:6447:900:1101::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:101::3'),
(12, 'vpn-gw-1', '10.11.2.0', '24', '10.2.0.0', '24', '10.1.2.3', '2a04:6447:900:1102::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:102::3'),
(13, 'vpn-gw-2', '10.21.0.0', '24', '10.2.0.0', '24', '10.1.0.3', '2a04:6447:900:2100::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:100::3'),
(14, 'vpn-gw-2', '10.21.1.0', '24', '10.2.0.0', '24', '10.1.1.3', '2a04:6447:900:2101::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:101::3'),
(15, 'vpn-gw-2', '10.21.2.0', '24', '10.2.0.0', '24', '10.1.2.3', '2a04:6447:900:2102::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:102::3'),
(16, 'vpn-gw-3', '10.31.0.0', '24', '10.2.0.0', '24', '10.1.0.3', '2a04:6447:900:3100::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:100::3'),
(17, 'vpn-gw-3', '10.31.1.0', '24', '10.2.0.0', '24', '10.1.1.3', '2a04:6447:900:3101::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:101::3'),
(18, 'vpn-gw-3', '10.31.2.0', '24', '10.2.0.0', '24', '10.1.2.3', '2a04:6447:900:3102::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:102::3'),
(19, 'vpn-gw-4', '10.41.0.0', '24', '10.2.0.0', '24', '10.1.0.3', '2a04:6447:900:4100::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:100::3'),
(20, 'vpn-gw-4', '10.41.1.0', '24', '10.2.0.0', '24', '10.1.1.3', '2a04:6447:900:4101::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:101::3'),
(21, 'vpn-gw-4', '10.41.2.0', '24', '10.2.0.0', '24', '10.1.2.3', '2a04:6447:900:4102::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:102::3'),
(22, 'vpn-gw-5', '10.51.0.0', '24', '10.2.0.0', '24', '10.1.0.3', '2a04:6447:900:5100::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:100::3'),
(23, 'vpn-gw-5', '10.51.1.0', '24', '10.2.0.0', '24', '10.1.1.3', '2a04:6447:900:5101::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:101::3'),
(24, 'vpn-gw-5', '10.51.2.0', '24', '10.2.0.0', '24', '10.1.2.3', '2a04:6447:900:5102::', '64', '2a04:6447:900:200::', '64', '2a04:6447:900:102::3');

-- --------------------------------------------------------

--
-- Table structure for table `host_script`
--

CREATE TABLE `host_script` (
  `id` int NOT NULL,
  `Name` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `config_script` text COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `host_script`
--

INSERT INTO `host_script` (`id`, `Name`, `config_script`) VALUES
(1, 'cl1-gw1', 'set as 64512\r\nset router-id 172.23.23.177\r\n\r\nset bgp external remote-as 64513 on\r\n\r\nset routemap BGP-In id 10 on\r\nset routemap BGP-In id 10 allow\r\nset routemap BGP-In id 10 match aspath-regex \".*\" origin any\r\n\r\nset routemap BGP-Out id 10 on\r\nset routemap BGP-Out id 10 restrict\r\nset routemap BGP-Out id 10 match network 2a04:6447:900:300::/64 exact restrict on\r\nset routemap BGP-Out id 10 match protocol static\r\n\r\nset routemap BGP-Out id 12 on\r\nset routemap BGP-Out id 12 restrict\r\nset routemap BGP-Out id 12 match network 10.3.0.0/24 exact restrict on\r\nset routemap BGP-Out id 12 match protocol static\r\n\r\nset routemap BGP-Out id 15 on\r\nset routemap BGP-Out id 15 allow\r\nset routemap BGP-Out id 15 match protocol static\r\n\r\nset routemap BGP-Out-vlan100 id 5 on\r\nset routemap BGP-Out-vlan100 id 5 allow\r\nset routemap BGP-Out-vlan100 id 5 match interface eth1-01.100 on\r\nset routemap BGP-Out-vlan100 id 5 match interface eth1-01.101 on\r\nset routemap BGP-Out-vlan100 id 5 match interface eth1-01.102 on\r\nset routemap BGP-Out-vlan100 id 5 match protocol direct\r\n\r\nset bgp external remote-as 64513 local-address 2a04:6447:900:200::1 on\r\n\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 capability ipv6-unicast on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 capability ipv4-unicast off\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 multihop on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 keepalive 30\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 send-keepalives on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 authtype md5 secret vpn123\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 graceful-restart on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 export-routemap \"BGP-Out\" preference 1 family inet6 on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 export-routemap \"BGP-Out-vlan100\" preference 2 family inet6 on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 import-routemap \"BGP-In\" preference 1 family inet6 on\r\n\r\ndelete vpn tunnel 1\r\nset bgp external remote-as 64513 peer 6000::63 off\r\nset bgp external remote-as 64513 peer 172.16.30.3 off\r\n'),
(2, 'cl1-gw2', 'set as 64512\r\nset router-id 172.23.23.177\r\nset bgp external remote-as 64513 on\r\n\r\nset routemap BGP-In id 10 on\r\nset routemap BGP-In id 10 allow\r\nset routemap BGP-In id 10 match aspath-regex \".*\" origin any\r\n\r\nset routemap BGP-Out id 10 on\r\nset routemap BGP-Out id 10 restrict\r\nset routemap BGP-Out id 10 match network 2a04:6447:900:300::/64 exact restrict on\r\nset routemap BGP-Out id 10 match protocol static\r\n\r\nset routemap BGP-Out id 12 on\r\nset routemap BGP-Out id 12 restrict\r\nset routemap BGP-Out id 12 match network 10.3.0.0/24 exact restrict on\r\nset routemap BGP-Out id 12 match protocol static\r\n\r\nset routemap BGP-Out id 15 on\r\nset routemap BGP-Out id 15 allow\r\nset routemap BGP-Out id 15 match protocol static\r\n\r\nset routemap BGP-Out-vlan100 id 5 on\r\nset routemap BGP-Out-vlan100 id 5 allow\r\nset routemap BGP-Out-vlan100 id 5 match interface eth1-01.100 on\r\nset routemap BGP-Out-vlan100 id 5 match interface eth1-01.101 on\r\nset routemap BGP-Out-vlan100 id 5 match interface eth1-01.102 on\r\nset routemap BGP-Out-vlan100 id 5 match protocol direct\r\n\r\nset bgp external remote-as 64513 local-address 2a04:6447:900:200::2 on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 capability ipv6-unicast on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 capability ipv4-unicast off\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 multihop on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 keepalive 30\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 send-keepalives on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 authtype md5 secret vpn123\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 graceful-restart on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 export-routemap \"BGP-Out\" preference 1 family inet6 on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 export-routemap \"BGP-Out-vlan100\" preference 2 family inet6 on\r\nset bgp external remote-as 64513 peer 2a04:6447:900:300::3 import-routemap \"BGP-In\" preference 1 family inet6 on\r\n\r\ndelete vpn tunnel 1\r\nset bgp external remote-as 64513 peer 6000::63 off\r\nset bgp external remote-as 64513 peer 172.16.30.3 off\r\n'),
(3, 'cl2-gw1', 'set as 64513\r\nset router-id 172.23.23.108\r\n\r\nset bgp external remote-as 64512 on\r\n\r\nset routemap BGP-In id 10 on\r\nset routemap BGP-In id 10 allow\r\nset routemap BGP-In id 10 match aspath-regex \".*\" origin any\r\n\r\nset routemap BGP-Out-vlan400 id 10 on\r\nset routemap BGP-Out-vlan400 id 10 allow\r\nset routemap BGP-Out-vlan400 id 10 match interface eth1-02.400 on\r\nset routemap BGP-Out-vlan400 id 10 match protocol direct\r\n\r\nset bgp external remote-as 64512 local-address 2a04:6447:900:300::1 on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 capability ipv6-unicast on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 capability ipv4-unicast off\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 multihop on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 keepalive 30\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 send-keepalives on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 authtype md5 secret vpn123\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 graceful-restart on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 export-routemap \"BGP-Out-vlan400\" preference 1 family inet6 on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 import-routemap \"BGP-In\" preference 1 family inet6 on\r\n\r\ndelete vpn tunnel 1\r\nset bgp external remote-as 64513 peer 5000::63 off\r\nset bgp external remote-as 64513 peer 172.16.20.3 off\r\n'),
(4, 'cl2-gw2', 'set as 64513\r\nset router-id 172.23.23.108\r\n\r\nset bgp external remote-as 64512 on\r\n\r\nset routemap BGP-In id 10 on\r\nset routemap BGP-In id 10 allow\r\nset routemap BGP-In id 10 match aspath-regex \".*\" origin any\r\n\r\n\r\nset routemap BGP-Out-vlan400 id 10 on\r\nset routemap BGP-Out-vlan400 id 10 allow\r\nset routemap BGP-Out-vlan400 id 10 match interface eth1-02.400 on\r\nset routemap BGP-Out-vlan400 id 10 match protocol direct\r\n\r\nset bgp external remote-as 64512 local-address 2a04:6447:900:300::2 on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 capability ipv6-unicast on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 capability ipv4-unicast off\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 multihop on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 keepalive 30\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 send-keepalives on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 authtype md5 secret vpn123\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 graceful-restart on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 export-routemap \"BGP-Out-vlan400\" preference 1 family inet6 on\r\nset bgp external remote-as 64512 peer 2a04:6447:900:200::3 import-routemap \"BGP-In\" preference 1 family inet6 on\r\n\r\ndelete vpn tunnel 1\r\nset bgp external remote-as 64513 peer 5000::63 off\r\nset bgp external remote-as 64513 peer 172.16.20.3 off\r\n'),
(5, 'vpn-gw-1', 'add static-route-ipv6 nexthop gateway ipv6-address 2a04:6447:900:100::3 priority 10 ipv6-destination 2a04:6447:900:500::/64\nadd static-route nexthop gateway ipv4-address 10.1.0.3 destination 172.23.23.0/24\n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:1100::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:1101::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:1102::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.11.0.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.11.1.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.11.2.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\" \n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:1100::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:1101::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:1102::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.11.0.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.11.1.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.11.2.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\" \n\n#add static-route-ipv6 ipv6-source 2a04:6447:900:1100::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:100::3 \n#add static-route-ipv6 ipv6-source 2a04:6447:900:1101::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:101::3 \n#add static-route-ipv6 ipv6-source 2a04:6447:900:1102::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:102::3 '),
(6, 'vpn-gw-2', 'add static-route-ipv6 nexthop gateway ipv6-address 2a04:6447:900:100::3 priority 10 ipv6-destination 2a04:6447:900:500::/64\nadd static-route nexthop gateway ipv4-address 10.1.0.3 destination 172.23.23.0/24\n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:2100::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:2101::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:2102::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.21.0.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.21.1.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.21.2.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\" \n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:2100::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:2101::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:2102::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.21.0.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.21.1.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.21.2.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\" \n'),
(7, 'vpn-gw-3', 'add static-route-ipv6 nexthop gateway ipv6-address 2a04:6447:900:100::3 priority 10 ipv6-destination 2a04:6447:900:500::/64\nadd static-route nexthop gateway ipv4-address 10.1.0.3 destination 172.23.23.0/24\n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:3100::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:3101::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:3102::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.31.0.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.31.1.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.31.2.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\" \n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:3100::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:3101::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:3102::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.31.0.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.31.1.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.31.2.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\" \n'),
(8, 'vpn-gw-4', 'add static-route-ipv6 nexthop gateway ipv6-address 2a04:6447:900:100::3 priority 10 ipv6-destination 2a04:6447:900:500::/64\nadd static-route nexthop gateway ipv4-address 10.1.0.3 destination 172.23.23.0/24\n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:4100::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:4101::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:4102::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.41.0.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.41.1.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.41.2.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\" \n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:4100::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:4101::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:4102::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.41.0.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.41.1.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.41.2.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\" \n\n\n#add static-route-ipv6 ipv6-source 2a04:6447:900:4100::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:100::3 \n#add static-route-ipv6 ipv6-source 2a04:6447:900:4101::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:101::3 \n#add static-route-ipv6 ipv6-source 2a04:6447:900:4102::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:102::3 '),
(9, 'vpn-gw-5', 'add static-route-ipv6 nexthop gateway ipv6-address 2a04:6447:900:100::3 priority 10 ipv6-destination 2a04:6447:900:500::/64\nadd static-route nexthop gateway ipv4-address 10.1.0.3 destination 172.23.23.0/24\n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:5100::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:5101::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:5102::/64\" ipv6-destination \"2a04:6447:900:200::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.51.0.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.51.1.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.51.2.0/24\" destination \"10.2.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\"\n\nadd static-route-ipv6 ipv6-source \"2a04:6447:900:5100::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:100::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:5101::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:101::3\" \nadd static-route-ipv6 ipv6-source \"2a04:6447:900:5102::/64\" ipv6-destination \"2a04:6447:900:400::/64\" nexthop gateway ipv6-address \"2a04:6447:900:102::3\" \nadd static-route source \"10.51.0.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.0.3\" \nadd static-route source \"10.51.1.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.1.3\" \nadd static-route source \"10.51.2.0/24\" destination \"10.4.0.0/24\" nexthop gateway ipv4-address \"10.1.2.3\"\n\n#add static-route-ipv6 ipv6-source 2a04:6447:900:5100::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:100::3 \n#add static-route-ipv6 ipv6-source 2a04:6447:900:5101::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:101::3 \n#add static-route-ipv6 ipv6-source 2a04:6447:900:5102::/64 ipv6-destination ::/0 nexthop gateway ipv6-address 2a04:6447:900:102::3 \n');

-- --------------------------------------------------------

--
-- Table structure for table `host_static_routes`
--

CREATE TABLE `host_static_routes` (
  `id` int NOT NULL,
  `Name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `destV4` varchar(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `destV4_mask` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nexthopV4` varchar(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `destV6` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `destV6_prefix` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nexthopv6` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `host_static_routes`
--

INSERT INTO `host_static_routes` (`id`, `Name`, `destV4`, `destV4_mask`, `nexthopV4`, `destV6`, `destV6_prefix`, `nexthopv6`) VALUES
(10, 'vpn-gw-1', '172.23.23.0', '24', '10.1.0.3', '2a04:6447:900:500::', '64', '2a04:6447:900:100::3'),
(13, 'vpn-gw-2', '172.23.23.0', '24', '10.1.0.3', '2a04:6447:900:500::', '64', '2a04:6447:900:100::3'),
(16, 'vpn-gw-3', '172.23.23.0', '24', '10.1.0.3', '2a04:6447:900:500::', '64', '2a04:6447:900:100::3'),
(19, 'vpn-gw-4', '172.23.23.0', '24', '10.1.0.3', '2a04:6447:900:500::', '64', '2a04:6447:900:100::3'),
(22, 'vpn-gw-5', '172.23.23.0', '24', '10.1.0.3', '2a04:6447:900:500::', '64', '2a04:6447:900:100::3'),
(25, 'cl1-gw1', '10.11.0.0', '24', '10.1.0.10', '2a04:6447:900:1100::', '64', '2a04:6447:900:100::10'),
(26, 'cl1-gw1', '10.11.1.0', '24', '10.1.1.10', '2a04:6447:900:1101::', '64', '2a04:6447:900:101::10'),
(27, 'cl1-gw1', '10.11.2.0', '24', '10.1.2.10', '2a04:6447:900:1102::', '64', '2a04:6447:900:102::10'),
(28, 'cl1-gw1', '10.21.0.0', '24', '10.1.0.20', '2a04:6447:900:2100::', '64', '2a04:6447:900:100::20'),
(29, 'cl1-gw1', '10.21.1.0', '24', '10.1.1.20', '2a04:6447:900:2101::', '64', '2a04:6447:900:101::20'),
(30, 'cl1-gw1', '10.21.2.0', '24', '10.1.2.20', '2a04:6447:900:2102::', '64', '2a04:6447:900:102::20'),
(31, 'cl1-gw1', '10.31.0.0', '24', '10.1.0.30', '2a04:6447:900:3100::', '64', '2a04:6447:900:100::30'),
(32, 'cl1-gw1', '10.31.1.0', '24', '10.1.1.30', '2a04:6447:900:3101::', '64', '2a04:6447:900:101::30'),
(33, 'cl1-gw1', '10.31.2.0', '24', '10.1.2.30', '2a04:6447:900:3102::', '64', '2a04:6447:900:102::40'),
(34, 'cl1-gw1', '10.41.0.0', '24', '10.1.0.40', '2a04:6447:900:4100::', '64', '2a04:6447:900:100::40'),
(35, 'cl1-gw1', '10.41.1.0', '24', '10.1.1.40', '2a04:6447:900:4101::', '64', '2a04:6447:900:101::40'),
(36, 'cl1-gw1', '10.41.2.0', '24', '10.1.2.40', '2a04:6447:900:4102::', '64', '2a04:6447:900:102::40'),
(37, 'cl1-gw1', '10.51.0.0', '24', '10.1.0.50', '2a04:6447:900:5100::', '64', '2a04:6447:900:100::50'),
(38, 'cl1-gw1', '10.51.1.0', '24', '10.1.1.50', '2a04:6447:900:5101::', '64', '2a04:6447:900:101::50'),
(39, 'cl1-gw1', '10.51.2.0', '24', '10.1.2.50', '2a04:6447:900:5102::', '64', '2a04:6447:900:102::50'),
(40, 'cl1-gw1', '10.3.0.0', '24', '10.2.0.10', '2a04:6447:900:300::', '64', '2a04:6447:900:200::10'),
(41, 'cl2-gw1', '10.2.0.0', '24', '10.3.0.10', '2a04:6447:900:200::', '64', '2a04:6447:900:300::10'),
(42, 'cl2-gw2', '10.2.0.0', '24', '10.3.0.10', '2a04:6447:900:200::', '64', '2a04:6447:900:300::10');

-- --------------------------------------------------------

--
-- Table structure for table `host_vpn_interfaces`
--

CREATE TABLE `host_vpn_interfaces` (
  `id` int NOT NULL,
  `Name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `interface` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `vlan` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `ip_version` enum('ipv4','ipv6') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `next_hop_ip` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `redundancy_mode` enum('active','backup') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `priority` varchar(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '1',
  `order_index` int NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `host_vpn_interfaces`
--

INSERT INTO `host_vpn_interfaces` (`id`, `Name`, `interface`, `vlan`, `ip_version`, `next_hop_ip`, `redundancy_mode`, `priority`, `enabled`, `order_index`) VALUES
(1, 'vpn-gw-1', 'WAN', '100', 'ipv6', '', 'active', '', 1, 10),
(2, 'vpn-gw-1', 'WAN', '100', 'ipv4', '', 'active', '', 1, 11),
(4, 'vpn-gw-1', 'WAN', '101', 'ipv4', '10.1.1.3', 'backup', '2', 1, 21),
(6, 'vpn-gw-1', 'WAN', '102', 'ipv4', '10.1.2.3', 'backup', '4', 1, 31),
(7, 'vpn-gw-2', 'WAN', '100', 'ipv6', '', 'active', '', 1, 10),
(8, 'vpn-gw-2', 'WAN', '100', 'ipv4', '', 'active', '', 1, 11),
(9, 'vpn-gw-2', 'WAN', '101', 'ipv6', '', 'active', '', 1, 20),
(10, 'vpn-gw-2', 'WAN', '101', 'ipv4', '', 'active', '', 1, 21),
(11, 'vpn-gw-2', 'WAN', '102', 'ipv6', '', 'active', '', 1, 30),
(12, 'vpn-gw-2', 'WAN', '102', 'ipv4', '', 'active', '', 1, 31),
(13, 'vpn-gw-3', 'WAN', '100', 'ipv6', '', 'active', '', 1, 10),
(14, 'vpn-gw-3', 'WAN', '100', 'ipv4', '', 'active', '', 1, 11),
(15, 'vpn-gw-3', 'WAN', '101', 'ipv6', '', 'active', '', 1, 20),
(16, 'vpn-gw-3', 'WAN', '101', 'ipv4', '', 'active', '', 1, 21),
(17, 'vpn-gw-3', 'WAN', '102', 'ipv6', '', 'active', '', 1, 30),
(18, 'vpn-gw-3', 'WAN', '102', 'ipv4', '', 'active', '', 1, 31),
(19, 'vpn-gw-4', 'WAN', '100', 'ipv6', '', 'active', '', 1, 10),
(20, 'vpn-gw-4', 'WAN', '100', 'ipv4', '', 'active', '', 1, 11),
(21, 'vpn-gw-4', 'WAN', '101', 'ipv6', '', 'active', '', 1, 20),
(22, 'vpn-gw-4', 'WAN', '101', 'ipv4', '', 'active', '', 1, 21),
(23, 'vpn-gw-4', 'WAN', '102', 'ipv6', '', 'active', '', 1, 30),
(24, 'vpn-gw-4', 'WAN', '102', 'ipv4', '', 'active', '', 1, 31),
(25, 'vpn-gw-5', 'WAN', '100', 'ipv6', '', 'active', '', 1, 10),
(26, 'vpn-gw-5', 'WAN', '100', 'ipv4', '', 'active', '', 1, 11),
(27, 'vpn-gw-5', 'WAN', '101', 'ipv6', '', 'active', '', 1, 20),
(28, 'vpn-gw-5', 'WAN', '101', 'ipv4', '', 'active', '', 1, 21),
(29, 'vpn-gw-5', 'WAN', '102', 'ipv6', '', 'active', '', 1, 30),
(30, 'vpn-gw-5', 'WAN', '102', 'ipv4', '', 'active', '', 1, 31),
(57, 'cl1', 'eth1-01', '100', 'ipv6', '', 'active', '', 1, 10),
(58, 'cl1', 'eth1-01', '100', 'ipv4', '', 'active', '', 1, 11),
(59, 'cl1', 'eth1-01', '101', 'ipv4', '10.1.1.9', 'backup', '1', 1, 20),
(61, 'cl1', 'eth1-01', '102', 'ipv4', '10.1.2.9', 'backup', '3', 1, 30),
(63, 'cl1', 'eth1-02', '200', 'ipv4', '10.2.0.9', 'backup', '5', 1, 31);

-- --------------------------------------------------------

--
-- Table structure for table `Mgmt_server`
--

CREATE TABLE `Mgmt_server` (
  `Mgmt_Server_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Mgmt_Server_IPv4` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Mgmt_Server_IPv6` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `Mgmt_server`
--

INSERT INTO `Mgmt_server` (`Mgmt_Server_name`, `Mgmt_Server_IPv4`, `Mgmt_Server_IPv6`) VALUES
('Server1', '172.23.23.13', '2a04:6447:900:500::13'),
('Server2', '172.23.23.19', '5000::63');

-- --------------------------------------------------------

--
-- Table structure for table `templates`
--

CREATE TABLE `templates` (
  `id` int NOT NULL,
  `Name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Content` text COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `templates`
--

INSERT INTO `templates` (`id`, `Name`, `Content`) VALUES
(1, 'Feak-Spark', 'set hostname {{hosts:Name}}\r\n\r\nset property first-time-wizard off\r\nkernel-parameter set type int name vpn_source_based_tpi value 1\r\nset expert password-hash $1$DBUpzBmW$cE3Rk0immvlj0/VZTihsZ/\r\n\r\n::Sleep 2\r\ndelete interface LAN1_Switch\r\n::Sleep 5\r\n\r\n# ---- Base interfaces (VLAN or not) ----\r\n::Loop table=vw_base_if\r\nset interface {{interface}} unassigned\r\nset interface {{interface}} state on\r\nset dhcp-ipv6 server interface {{interface}} disable\r\n::LoopEND\r\n\r\n# ---- Non-VLAN IPv6 (only when present) ----\r\n::Loop table=vw_v6_novlan\r\nset interface {{interface}} ipv6-address {{ipv6_addr}} ipv6-prefix-length {{prefix}}\r\n::LoopEND\r\n\r\n# ---- Non-VLAN IPv4 (only when present) ----\r\n::Loop table=vw_v4_novlan\r\nset interface {{interface}} ipv4-address {{ipv4_addr}} mask-length {{IPv4_mask-len}}\r\n::LoopEND\r\n\r\n# ---- WAN VLAN connections (IPv6 and/or IPv4; rows without a family simply won’t render those lines) ----\r\n::Loop table=vw_wans\r\nadd internet-connection-ipv6 interface-ipv6 WAN type-ipv6 static-ipv6 ipv6-address {{ipv6_addr}} default-gw-ipv6 {{ipv6_defaultgw}} prefix-length {{prefix}} use-connection-as-vlan vlan-id {{vlan}}\r\nadd internet-connection interface WAN type static ipv4-address {{ipv4_addr}} default-gw {{ipv4_defaultgw}} mask-length {{IPv4_mask-len}} use-connection-as-vlan vlan-id {{vlan}}\r\n::LoopEND\r\n\r\n# ---- Static routes (family-specific; emit only when rows exist) ----\r\n::Loop table=host_static_routes\r\nadd static-route-ipv6 nexthop gateway ipv6-address {{nexthopV6}} priority 10 ipv6-destination {{destV6}}/{{destV6_prefix}}\r\nadd static-route nexthop gateway ipv4-address {{nexthopV4}} destination {{destV4}}/{{destV4_mask}}\r\n::LoopEND\r\n\r\n::Loop table=host_routes\r\nadd static-route-ipv6 ipv6-source \"{{SourceV6}}/{{sourceV6_prefix}}\" nexthop gateway ipv6-address \"{{nexthopV6}}\" ipv6-destination \"{{destV6}}/{{destV6_prefix}}\"\r\nadd static-route source \"{{SourceV4}}/{{sourceV4_mask}}\" nexthop gateway ipv4-address \"{{nexthopV4}}\" destination \"{{destV4}}/{{destV4_mask}}\"\r\n::LoopEND\r\n\r\nset security-management mode centrally-managed\r\nset sic_init password {{netvars:hosts:otp}}\r\n\r\nset internet-connection Internet1 probe-servers off\r\nset internet-connection Internet2 probe-servers off\r\nset internet-connection Internet3 probe-servers off\r\nset internet-connection Internet4 probe-servers off\r\nset internet-connection Internet5 probe-servers off\r\nset internet-connection Internet6 probe-servers off\r\n\r\nset ntp local-time-zone \"TIMEZONE.AMSTERDAM_BERLIN_BERN_ROME_STOCKHOLM_VIENNA\" auto-adjust-daylight-saving \"on\" auto-timeZone \"off\" local-server \"off\"\r\nset ntp server primary \"2a04:6447:900:200::100\" auto-adjust-daylight-saving \"on\" auto-timeZone \"off\"\r\nset ntp server secondary 10.2.0.10 auto-adjust-daylight-saving \"on\" auto-timeZone \"off\"\r\nset ntp interval \"5\"\r\nset ntp active \"on\"\r\n\r\n::ExpertMode command=expert prompt=\'password:\' {{hosts:expertpw}} expert-prompt=\'#\'\r\nls -al\r\ndate\r\n::ExpertModeEnd command=exit prompt=\'>\'\r\nshow interfaces table\r\n\r\n{{host_script:config_script}}\r\n'),
(2, 'Full-GAIA-GW', 'set hostname {{hosts:Name}}\r\n\r\n::Loop table=vw_hosts_mgmt_v6\r\nset interface Mgmt ipv6-address {{mgmt_IPv6_addr}} mask-length {{mgmt_IPv6_prefix}}\r\n::LoopEND\r\n\r\n::Loop table=vw_base_if\r\nset interface {{interface}} state on\r\n::LoopEND\r\n\r\n::Loop table=vw_sync_off\r\nset interface {{interface}} state off\r\n::LoopEND\r\n\r\n::Loop table=vw_lans\r\nadd interface {{interface}} vlan {{vlan}}\r\nset interface {{interface}}.{{vlan}} state on\r\n::LoopEND\r\n\r\n::Loop table=vw_v6_vlan\r\nset interface {{interface}}.{{vlan}} ipv6-address {{ipv6_addr}} mask-length {{prefix}}\r\n::LoopEND\r\n\r\n::Loop table=vw_v6_novlan\r\nset interface {{interface}} ipv6-address {{ipv6_addr}} mask-length {{prefix}}\r\n::LoopEND\r\n\r\n::Loop table=vw_v4_vlan\r\nset interface {{interface}}.{{vlan}} ipv4-address {{ipv4_addr}} mask-length {{IPv4_mask-len}}\r\n::LoopEND\r\n\r\n::Loop table=vw_v4_novlan\r\nset interface {{interface}} ipv4-address {{ipv4_addr}} mask-length {{IPv4_mask-len}}\r\n::LoopEND\r\n\r\nset static-route default nexthop gateway address 172.23.23.1 on\r\n\r\n::Loop table=vw_host_static_routes\r\nset ipv6 static-route {{dest_V6}}/{{dest_V6_prefix}} nexthop gateway {{nexthop_v6}} on\r\nset static-route {{dest_v4}}/{{dest_v4_mask}} nexthop gateway address {{nexthop_v4}} on\r\n::LoopEND\r\n\r\n::ExpertMode command=expert prompt=\'password:\' {{hosts:expertpw}} expert-prompt=\'#\'\r\nls -al\r\ndate\r\n::ExpertModeEnd command=exit prompt=\'>\'\r\n\r\n\r\nset routemap BGP-In id 10 on\r\nset routemap BGP-In id 10 allow\r\nset routemap BGP-In id 10 match aspath-regex \".*\" origin any\r\n\r\n\r\nset routemap BGP-Out-vlan400 id 10 on\r\nset routemap BGP-Out-vlan400 id 10 allow\r\nset routemap BGP-Out-vlan400 id 10 match interface eth1-02.400 on\r\nset routemap BGP-Out-vlan400 id 10 match protocol direct\r\n\r\n{{host_script:config_script}}\r\n');

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_base_if`
-- (See below for the actual view)
--
CREATE TABLE `vw_base_if` (
`interface` varchar(64)
,`Name` varchar(255)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_hosts_mgmt_v6`
-- (See below for the actual view)
--
CREATE TABLE `vw_hosts_mgmt_v6` (
`mgmt_IPv6_addr` varchar(255)
,`mgmt_IPv6_prefix` varchar(3)
,`Name` varchar(255)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_host_routes`
-- (See below for the actual view)
--
CREATE TABLE `vw_host_routes` (
`dest_v4` varchar(25)
,`dest_v4_mask` varchar(3)
,`dest_v6` varchar(255)
,`dest_v6_prefix` varchar(3)
,`Name` varchar(255)
,`nexthop_v4` varchar(25)
,`nexthop_v6` varchar(255)
,`source_v4` varchar(25)
,`source_v4_mask` varchar(3)
,`source_v6` varchar(255)
,`source_v6_prefix` varchar(3)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_host_static_routes`
-- (See below for the actual view)
--
CREATE TABLE `vw_host_static_routes` (
`dest_v4` varchar(25)
,`dest_v4_mask` varchar(3)
,`dest_v6` varchar(255)
,`dest_v6_prefix` varchar(3)
,`Name` varchar(255)
,`nexthop_v4` varchar(25)
,`nexthop_v6` varchar(255)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_host_vpn_interfaces`
-- (See below for the actual view)
--
CREATE TABLE `vw_host_vpn_interfaces` (
`enabled` tinyint(1)
,`id` int
,`interface` varchar(64)
,`interface_name` varchar(129)
,`ip_version` enum('ipv4','ipv6')
,`Name` varchar(255)
,`next_hop_ip` varchar(255)
,`order_index` bigint unsigned
,`order_index_raw` int
,`priority` varchar(3)
,`redundancy_mode` enum('active','backup')
,`vlan` varchar(64)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_lans`
-- (See below for the actual view)
--
CREATE TABLE `vw_lans` (
`interface` varchar(64)
,`ipv4_addr` varchar(64)
,`IPv4_mask-len` varchar(2)
,`ipv6_addr` varchar(64)
,`Name` varchar(255)
,`order_col` int
,`prefix` varchar(2)
,`vlan` varchar(64)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_sync_off`
-- (See below for the actual view)
--
CREATE TABLE `vw_sync_off` (
`interface` varchar(64)
,`Name` varchar(255)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_v4_novlan`
-- (See below for the actual view)
--
CREATE TABLE `vw_v4_novlan` (
`interface` varchar(64)
,`ipv4_addr` varchar(64)
,`IPv4_mask-len` varchar(2)
,`Name` varchar(255)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_v4_vlan`
-- (See below for the actual view)
--
CREATE TABLE `vw_v4_vlan` (
`interface` varchar(64)
,`ipv4_addr` varchar(64)
,`IPv4_mask-len` varchar(2)
,`Name` varchar(255)
,`vlan` varchar(64)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_v6_novlan`
-- (See below for the actual view)
--
CREATE TABLE `vw_v6_novlan` (
`interface` varchar(64)
,`ipv6_addr` varchar(64)
,`Name` varchar(255)
,`prefix` varchar(2)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_v6_vlan`
-- (See below for the actual view)
--
CREATE TABLE `vw_v6_vlan` (
`interface` varchar(64)
,`ipv6_addr` varchar(64)
,`Name` varchar(255)
,`prefix` varchar(2)
,`vlan` varchar(64)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_wans`
-- (See below for the actual view)
--
CREATE TABLE `vw_wans` (
`interface` varchar(64)
,`ipv4_addr` varchar(64)
,`ipv4_defaultgw` varchar(25)
,`IPv4_mask-len` varchar(2)
,`ipv6_addr` varchar(64)
,`ipv6_defaultgw` varchar(255)
,`Name` varchar(255)
,`prefix` varchar(2)
,`vlan` varchar(64)
);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `hosts`
--
ALTER TABLE `hosts`
  ADD PRIMARY KEY (`mgmt_IPv4_addr`,`Name`);

--
-- Indexes for table `host_interfaces`
--
ALTER TABLE `host_interfaces`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `host_internet_spark`
--
ALTER TABLE `host_internet_spark`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `host_routes`
--
ALTER TABLE `host_routes`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `host_script`
--
ALTER TABLE `host_script`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `host_static_routes`
--
ALTER TABLE `host_static_routes`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `host_vpn_interfaces`
--
ALTER TABLE `host_vpn_interfaces`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_host_if_ver` (`Name`,`interface`,`vlan`,`ip_version`);

--
-- Indexes for table `templates`
--
ALTER TABLE `templates`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `host_interfaces`
--
ALTER TABLE `host_interfaces`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=60;

--
-- AUTO_INCREMENT for table `host_internet_spark`
--
ALTER TABLE `host_internet_spark`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT for table `host_routes`
--
ALTER TABLE `host_routes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=25;

--
-- AUTO_INCREMENT for table `host_script`
--
ALTER TABLE `host_script`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `host_static_routes`
--
ALTER TABLE `host_static_routes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=43;

--
-- AUTO_INCREMENT for table `host_vpn_interfaces`
--
ALTER TABLE `host_vpn_interfaces`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=77;

--
-- AUTO_INCREMENT for table `templates`
--
ALTER TABLE `templates`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

-- --------------------------------------------------------

--
-- Structure for view `vw_base_if`
--
DROP TABLE IF EXISTS `vw_base_if`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_base_if`  AS SELECT DISTINCT `host_interfaces`.`Name` AS `Name`, `host_interfaces`.`interface` AS `interface` FROM `host_interfaces` WHERE ((`host_interfaces`.`interface` is not null) AND (`host_interfaces`.`interface` <> '')) ;

-- --------------------------------------------------------

--
-- Structure for view `vw_hosts_mgmt_v6`
--
DROP TABLE IF EXISTS `vw_hosts_mgmt_v6`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_hosts_mgmt_v6`  AS SELECT `hosts`.`Name` AS `Name`, `hosts`.`mgmt_IPv6_addr` AS `mgmt_IPv6_addr`, `hosts`.`mgmt_IPv6_prefix` AS `mgmt_IPv6_prefix` FROM `hosts` WHERE ((`hosts`.`mgmt_IPv6_addr` is not null) AND (`hosts`.`mgmt_IPv6_addr` <> '') AND (`hosts`.`mgmt_IPv6_prefix` is not null) AND (`hosts`.`mgmt_IPv6_prefix` <> '')) ;

-- --------------------------------------------------------

--
-- Structure for view `vw_host_routes`
--
DROP TABLE IF EXISTS `vw_host_routes`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_host_routes`  AS SELECT `host_routes`.`Name` AS `Name`, `host_routes`.`SourceV4` AS `source_v4`, `host_routes`.`sourceV4_mask` AS `source_v4_mask`, `host_routes`.`destV4` AS `dest_v4`, `host_routes`.`destV4_mask` AS `dest_v4_mask`, `host_routes`.`nexthopV4` AS `nexthop_v4`, `host_routes`.`SourceV6` AS `source_v6`, `host_routes`.`sourceV6_prefix` AS `source_v6_prefix`, `host_routes`.`destV6` AS `dest_v6`, `host_routes`.`destV6_prefix` AS `dest_v6_prefix`, `host_routes`.`nexthopV6` AS `nexthop_v6` FROM `host_routes` ;

-- --------------------------------------------------------

--
-- Structure for view `vw_host_static_routes`
--
DROP TABLE IF EXISTS `vw_host_static_routes`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_host_static_routes`  AS SELECT `host_static_routes`.`Name` AS `Name`, `host_static_routes`.`destV4` AS `dest_v4`, `host_static_routes`.`destV4_mask` AS `dest_v4_mask`, `host_static_routes`.`nexthopV4` AS `nexthop_v4`, `host_static_routes`.`destV6` AS `dest_v6`, `host_static_routes`.`destV6_prefix` AS `dest_v6_prefix`, `host_static_routes`.`nexthopv6` AS `nexthop_v6` FROM `host_static_routes` ;

-- --------------------------------------------------------

--
-- Structure for view `vw_host_vpn_interfaces`
--
DROP TABLE IF EXISTS `vw_host_vpn_interfaces`;

CREATE ALGORITHM=MERGE DEFINER=`root`@`%` SQL SECURITY INVOKER VIEW `vw_host_vpn_interfaces`  AS SELECT `hvi`.`id` AS `id`, `hvi`.`Name` AS `Name`, `hvi`.`interface` AS `interface`, `hvi`.`vlan` AS `vlan`, concat(`hvi`.`interface`,(case when ((`hvi`.`vlan` is null) or (`hvi`.`vlan` = '')) then '' else concat('.',`hvi`.`vlan`) end)) AS `interface_name`, `hvi`.`ip_version` AS `ip_version`, `hvi`.`next_hop_ip` AS `next_hop_ip`, `hvi`.`redundancy_mode` AS `redundancy_mode`, `hvi`.`priority` AS `priority`, `hvi`.`enabled` AS `enabled`, `hvi`.`order_index` AS `order_index_raw`, cast(coalesce(nullif(`hvi`.`priority`,''),`hvi`.`order_index`) as unsigned) AS `order_index` FROM `host_vpn_interfaces` AS `hvi` ;

-- --------------------------------------------------------

--
-- Structure for view `vw_lans`
--
DROP TABLE IF EXISTS `vw_lans`;

CREATE ALGORITHM=MERGE DEFINER=`root`@`%` SQL SECURITY INVOKER VIEW `vw_lans`  AS SELECT `hi`.`Name` AS `Name`, `hi`.`interface` AS `interface`, `hi`.`vlan` AS `vlan`, `hi`.`ipv4_addr` AS `ipv4_addr`, `hi`.`IPv4_mask-len` AS `IPv4_mask-len`, `hi`.`ipv6_addr` AS `ipv6_addr`, `hi`.`prefix` AS `prefix`, 0 AS `order_col` FROM `host_interfaces` AS `hi` WHERE ((`hi`.`vlan` is not null) AND (`hi`.`vlan` <> '')) ;

-- --------------------------------------------------------

--
-- Structure for view `vw_sync_off`
--
DROP TABLE IF EXISTS `vw_sync_off`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_sync_off`  AS SELECT `host_interfaces`.`Name` AS `Name`, `host_interfaces`.`interface` AS `interface` FROM `host_interfaces` WHERE (`host_interfaces`.`Sync` = 1) ;

-- --------------------------------------------------------

--
-- Structure for view `vw_v4_novlan`
--
DROP TABLE IF EXISTS `vw_v4_novlan`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_v4_novlan`  AS SELECT `host_interfaces`.`Name` AS `Name`, `host_interfaces`.`interface` AS `interface`, `host_interfaces`.`ipv4_addr` AS `ipv4_addr`, `host_interfaces`.`IPv4_mask-len` AS `IPv4_mask-len` FROM `host_interfaces` WHERE (((`host_interfaces`.`vlan` is null) OR (`host_interfaces`.`vlan` = '')) AND (`host_interfaces`.`ipv4_addr` is not null) AND (`host_interfaces`.`ipv4_addr` <> '')) ;

-- --------------------------------------------------------

--
-- Structure for view `vw_v4_vlan`
--
DROP TABLE IF EXISTS `vw_v4_vlan`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_v4_vlan`  AS SELECT `host_interfaces`.`Name` AS `Name`, `host_interfaces`.`interface` AS `interface`, `host_interfaces`.`vlan` AS `vlan`, `host_interfaces`.`ipv4_addr` AS `ipv4_addr`, `host_interfaces`.`IPv4_mask-len` AS `IPv4_mask-len` FROM `host_interfaces` WHERE ((`host_interfaces`.`vlan` is not null) AND (`host_interfaces`.`vlan` <> '') AND (`host_interfaces`.`ipv4_addr` is not null) AND (`host_interfaces`.`ipv4_addr` <> '')) ;

-- --------------------------------------------------------

--
-- Structure for view `vw_v6_novlan`
--
DROP TABLE IF EXISTS `vw_v6_novlan`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_v6_novlan`  AS SELECT `host_interfaces`.`Name` AS `Name`, `host_interfaces`.`interface` AS `interface`, `host_interfaces`.`ipv6_addr` AS `ipv6_addr`, `host_interfaces`.`prefix` AS `prefix` FROM `host_interfaces` WHERE (((`host_interfaces`.`vlan` is null) OR (`host_interfaces`.`vlan` = '')) AND (`host_interfaces`.`ipv6_addr` is not null) AND (`host_interfaces`.`ipv6_addr` <> '')) ;

-- --------------------------------------------------------

--
-- Structure for view `vw_v6_vlan`
--
DROP TABLE IF EXISTS `vw_v6_vlan`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`%` SQL SECURITY DEFINER VIEW `vw_v6_vlan`  AS SELECT `host_interfaces`.`Name` AS `Name`, `host_interfaces`.`interface` AS `interface`, `host_interfaces`.`vlan` AS `vlan`, `host_interfaces`.`ipv6_addr` AS `ipv6_addr`, `host_interfaces`.`prefix` AS `prefix` FROM `host_interfaces` WHERE ((`host_interfaces`.`vlan` is not null) AND (`host_interfaces`.`vlan` <> '') AND (`host_interfaces`.`ipv6_addr` is not null) AND (`host_interfaces`.`ipv6_addr` <> '')) ;

-- --------------------------------------------------------

--
-- Structure for view `vw_wans`
--
DROP TABLE IF EXISTS `vw_wans`;

CREATE ALGORITHM=MERGE DEFINER=`root`@`%` SQL SECURITY INVOKER VIEW `vw_wans`  AS SELECT `w`.`Name` AS `Name`, `w`.`interface` AS `interface`, `w`.`vlan` AS `vlan`, `w`.`ipv4_addr` AS `ipv4_addr`, `w`.`IPv4_mask-len` AS `IPv4_mask-len`, `w`.`ipv4_defaultgw` AS `ipv4_defaultgw`, `w`.`ipv6_addr` AS `ipv6_addr`, `w`.`prefix` AS `prefix`, `w`.`ipv6_defaultgw` AS `ipv6_defaultgw` FROM `host_internet_spark` AS `w` ;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
