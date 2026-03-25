import 'package:flutter/material.dart';

class StorytellingMobilePage extends StatelessWidget {
  const StorytellingMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1EA),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHero(context)),
            SliverToBoxAdapter(child: _buildFeatured(context)),
            SliverToBoxAdapter(child: _buildDiscovery(context)),
            SliverToBoxAdapter(child: _buildEditorial(context)),
            SliverToBoxAdapter(child: _buildSimpleList(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: SizedBox(
        height: 380,
        child: Stack(
          children: [
            Positioned(
              right: -50,
              top: -30,
              child: Container(
                width: 230,
                height: 230,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF20343A), Color(0xFF4F6A63)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                width: 175,
                height: 115,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0A436).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(32),
                ),
              ),
            ),
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Text(
                'CURATED STORIES',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.8,
                  color: const Color(0xFF2D3B3E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 60,
              right: 24,
              child: Text(
                'Ruang Temu\nIde, Visual,\ndan Rasa.',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 0.98,
                  color: const Color(0xFF11191B),
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 58,
              child: Container(
                width: 250,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF11191B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Tiap section punya ritme sendiri.',
                  style: TextStyle(
                    color: Color(0xFFF4F1EA),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 12,
              child: Transform.rotate(
                angle: -0.14,
                child: Container(
                  width: 95,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F4ED),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF20343A), width: 2),
                  ),
                  child: const Center(
                    child: Icon(Icons.play_arrow_rounded, size: 44, color: Color(0xFF20343A)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatured(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Konten Unggulan',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF11191B),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 42,
                  bottom: 0,
                  top: 24,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2E34),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vol. 09',
                          style: TextStyle(
                            color: Color(0xFFC8D7D1),
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Narasi Produk\nYang Menjual',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
                        Spacer(),
                        Text(
                          '12 menit baca',
                          style: TextStyle(color: Color(0xFFB7C8C3)),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 108,
                    height: 124,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0A436),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(Icons.auto_stories_rounded, size: 42, color: Color(0xFF1A2E34)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscovery(BuildContext context) {
    final items = [
      ('Future Retail', 'Eksperimen visual untuk toko modern', const Color(0xFF2A6A6D)),
      ('Motion Snippets', 'Gerak kecil yang terasa premium', const Color(0xFFA94E3A)),
      ('Interface Notes', 'Detail mikro yang membedakan produk', const Color(0xFF37494D)),
      ('Field Journal', 'Insight dari perilaku user harian', const Color(0xFF6A5332)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Penemuan',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF11191B),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 205,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final item = items[index];
                final isWide = index.isEven;
                return Container(
                  width: isWide ? 224 : 174,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: item.$3,
                    borderRadius: BorderRadius.circular(isWide ? 30 : 24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '0${index + 1}',
                        style: const TextStyle(
                          color: Color(0xFFE5ECE8),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        item.$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          color: Color(0xFFD7E3DE),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemCount: items.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorial(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: Color(0xFF1A2E34), width: 6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sorotan Editorial',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF11191B),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '"Produk yang terasa hidup selalu punya ritme: besar, tenang, lalu tajam."',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1B2A2C),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Editor Design Weekly  •  5 Maret 2026',
              style: TextStyle(
                color: Color(0xFF5A6B6B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleList(BuildContext context) {
    final listItems = [
      ('Behind The Scene Interface', 'Bagaimana tim menyusun detail visual'),
      ('Color and Trust', 'Kenapa palet hangat bisa menaikkan engagement'),
      ('From Brief to Narrative', 'Menyusun alur screen seperti cerita'),
      ('Spacing as Personality', 'Jarak antar elemen membentuk karakter'),
      ('Microcopy That Leads', 'Copy pendek untuk mengarahkan aksi user'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daftar Pilihan',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF11191B),
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(listItems.length, (index) {
            final item = listItems[index];
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF20343A).withValues(alpha: 0.18),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}'.padLeft(2, '0'),
                      style: const TextStyle(
                        color: Color(0xFF6B7D79),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: const TextStyle(
                            color: Color(0xFF11191B),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            color: Color(0xFF617170),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.north_east_rounded,
                    color: Color(0xFF1A2E34),
                    size: 19,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
