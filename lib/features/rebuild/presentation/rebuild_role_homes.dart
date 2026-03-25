import 'package:flutter/material.dart';

import 'rebuild_dashboard_shell.dart';

class PromotorRebuildHomePage extends StatelessWidget {
  const PromotorRebuildHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return RebuildRoleHomePage(
      config: const RebuildRoleHomeConfig(
        roleName: 'Promotor',
        userName: 'Promotor Kupang',
        primaryChip: 'Toko',
        secondaryInfo: 'Area Kupang',
        sections: [
          RebuildHomeSection(
            title: 'Target',
            subtitle: 'Target Harian, Mingguan, dan Bulanan',
            items: [
              'Target Sell Out All Type',
              'Target Produk Fokus',
              'Detail hitung target lewat klik detail',
            ],
          ),
          RebuildHomeSection(
            title: 'Bonus',
            subtitle: 'Ringkasan bonus berjalan',
            items: [
              'Bonus berjalan bulan ini',
              'Status pencapaian bonus',
            ],
          ),
          RebuildHomeSection(
            title: 'Aktivitas',
            subtitle: 'Aktivitas penting harian',
            items: [
              'Clock in',
              'Sell Out',
              'Stok',
              'Promosi',
              'Follower',
            ],
          ),
          RebuildHomeSection(
            title: 'Ranking Area SPV',
            subtitle: 'Urutan performa promotor dalam area',
            items: [
              'Posisi saat ini',
              'Leaderboard singkat',
            ],
          ),
        ],
      ),
    );
  }
}

class SatorRebuildHomePage extends StatelessWidget {
  const SatorRebuildHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return RebuildRoleHomePage(
      config: const RebuildRoleHomeConfig(
        roleName: 'SATOR',
        userName: 'SATOR Kupang',
        primaryChip: 'Jabatan',
        secondaryInfo: 'Area Kupang',
        sections: [
          RebuildHomeSection(
            title: 'Target Tim',
            subtitle: 'Target utama SATOR',
            items: [
              'Sell Out All Type',
              'Produk Fokus',
              'Sell In',
            ],
          ),
          RebuildHomeSection(
            title: 'Snapshot Tim',
            subtitle: 'Status tim hari ini',
            items: [
              'Jumlah promotor aktif',
              'Yang sudah jualan',
              'Yang belum jualan',
              'Toko aktif',
            ],
          ),
          RebuildHomeSection(
            title: 'Alert Operasional',
            subtitle: 'Masalah yang perlu ditindak',
            items: [
              'Promotor belum aktif',
              'Target tertinggal',
              'Pekerjaan nyangkut',
            ],
          ),
          RebuildHomeSection(
            title: 'Quick Access',
            subtitle: 'Pintu masuk menu kerja utama',
            items: [
              'Visiting',
              'Sell Out Monitoring',
              'Sell In Monitoring',
              'Jadwal',
            ],
          ),
        ],
      ),
    );
  }
}

class SpvRebuildHomePage extends StatelessWidget {
  const SpvRebuildHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return RebuildRoleHomePage(
      config: const RebuildRoleHomeConfig(
        roleName: 'SPV',
        userName: 'SPV Kupang',
        primaryChip: 'Jabatan',
        secondaryInfo: 'Area Kupang',
        sections: [
          RebuildHomeSection(
            title: 'Target Area',
            subtitle: 'Target utama area',
            items: [
              'Sell Out All Type',
              'Produk Fokus',
              'Sell In',
            ],
          ),
          RebuildHomeSection(
            title: 'Snapshot Struktur',
            subtitle: 'Struktur tim area',
            items: [
              'Jumlah SATOR',
              'Jumlah promotor',
              'Jumlah toko',
            ],
          ),
          RebuildHomeSection(
            title: 'Progress Monitoring',
            subtitle: 'Pantau kerja tim',
            items: [
              'Progress Sell Out',
              'Progress Sell In',
              'Progress Visiting',
              'Approval pending',
              'Nyangkut di siapa',
            ],
          ),
          RebuildHomeSection(
            title: 'Quick Access',
            subtitle: 'Aksi utama SPV',
            items: [
              'Monitor SATOR',
              'Monitor promotor',
              'Approval',
              'Stok',
            ],
          ),
        ],
      ),
    );
  }
}

class TrainerRebuildHomePage extends StatelessWidget {
  const TrainerRebuildHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return RebuildRoleHomePage(
      config: const RebuildRoleHomeConfig(
        roleName: 'Trainer',
        userName: 'Trainer Kupang',
        primaryChip: 'Jabatan',
        secondaryInfo: 'Area Kupang',
        sections: [
          RebuildHomeSection(
            title: 'Produk Fokus',
            subtitle: 'Produk fokus aktif untuk training',
            items: [
              'Daftar produk fokus bulan berjalan',
              'Ringkasan performa produk fokus',
            ],
          ),
          RebuildHomeSection(
            title: 'Materi Training',
            subtitle: 'Bahan untuk promotor',
            items: [
              'Fitur unggulan produk',
              'Poin perbandingan antar brand',
            ],
          ),
          RebuildHomeSection(
            title: 'Promotor Learning',
            subtitle: 'Akses belajar promotor',
            items: [
              'Materi yang bisa dipelajari promotor',
              'Akses komparasi produk',
            ],
          ),
          RebuildHomeSection(
            title: 'Ranking Promotor',
            subtitle: 'Pantau urutan performa promotor',
            items: [
              'Ranking promotor',
              'Performa Sell Out',
              'Performa Produk Fokus',
            ],
          ),
        ],
      ),
    );
  }
}

class ManagerRebuildHomePage extends StatelessWidget {
  const ManagerRebuildHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return RebuildRoleHomePage(
      config: const RebuildRoleHomeConfig(
        roleName: 'Manager',
        userName: 'Manager Kupang',
        primaryChip: 'Jabatan',
        secondaryInfo: 'Area Kupang',
        sections: [
          RebuildHomeSection(
            title: 'Business Snapshot',
            subtitle: 'Ringkasan pencapaian bisnis',
            items: [
              'Sell Out All Type',
              'Produk Fokus',
              'Sell In',
            ],
          ),
          RebuildHomeSection(
            title: 'SPV Control',
            subtitle: 'Kontrol kerja SPV',
            items: [
              'Pencapaian SPV',
              'Status kerja SPV',
              'SPV bermasalah',
            ],
          ),
          RebuildHomeSection(
            title: 'Area Alert',
            subtitle: 'Titik merah yang perlu perhatian',
            items: [
              'Area tertinggal',
              'Bottleneck utama',
            ],
          ),
          RebuildHomeSection(
            title: 'Quick Access',
            subtitle: 'Akses cepat manager',
            items: [
              'Ranking SPV',
              'Ranking SATOR',
              'Ranking promotor',
              'Business monitoring',
            ],
          ),
        ],
      ),
    );
  }
}

class AdminRebuildHomePage extends StatelessWidget {
  const AdminRebuildHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return RebuildRoleHomePage(
      config: const RebuildRoleHomeConfig(
        roleName: 'Admin',
        userName: 'Admin System',
        primaryChip: 'Pusat Kontrol',
        secondaryInfo: 'Area Kupang',
        sections: [
          RebuildHomeSection(
            title: 'System Snapshot',
            subtitle: 'Ringkasan status sistem',
            items: [
              'User aktif',
              'Hierarchy aktif',
              'Periode target aktif',
            ],
          ),
          RebuildHomeSection(
            title: 'User Snapshot',
            subtitle: 'Pantau semua role',
            items: [
              'Manager',
              'Trainer',
              'SPV',
              'SATOR',
              'Promotor',
            ],
          ),
          RebuildHomeSection(
            title: 'Target Snapshot',
            subtitle: 'Kontrol target dan bobot minggu',
            items: [
              'Periode target',
              'Bobot minggu',
              'Target per user',
            ],
          ),
          RebuildHomeSection(
            title: 'Quick Access',
            subtitle: 'Pintu masuk modul admin',
            items: [
              'User Management',
              'Hierarchy',
              'Store Assignment',
              'Produk Fokus',
              'Master Data',
            ],
          ),
        ],
      ),
    );
  }
}
