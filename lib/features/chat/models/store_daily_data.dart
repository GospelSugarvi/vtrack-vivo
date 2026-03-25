class StoreDailyData {
  final String storeName;
  final DateTime dateChecked;
  final int totalPromotors;
  final int presentPromotors;
  final int absentPromotors;
  final int totalStock;
  final int totalSales;
  final double totalOmzet;
  final int totalFokus;
  final double achievementPercentage;
  final int promotionPosts;

  const StoreDailyData({
    required this.storeName,
    required this.dateChecked,
    required this.totalPromotors,
    required this.presentPromotors,
    required this.absentPromotors,
    required this.totalStock,
    required this.totalSales,
    required this.totalOmzet,
    required this.totalFokus,
    required this.achievementPercentage,
    required this.promotionPosts,
  });

  factory StoreDailyData.fromJson(Map<String, dynamic> json) {
    return StoreDailyData(
      storeName: (json['store_name'] as String?) ?? 'Unknown Store',
      dateChecked: json['date_checked'] != null 
          ? DateTime.parse(json['date_checked'] as String)
          : DateTime.now(),
      totalPromotors: (json['total_promotors'] as int?) ?? 0,
      presentPromotors: (json['present_promotors'] as int?) ?? 0,
      absentPromotors: (json['absent_promotors'] as int?) ?? 0,
      totalStock: (json['total_stock'] as int?) ?? 0,
      totalSales: (json['total_sales'] as int?) ?? 0,
      totalOmzet: ((json['total_omzet'] as num?) ?? 0).toDouble(),
      totalFokus: (json['total_fokus'] as int?) ?? 0,
      achievementPercentage: ((json['achievement_percentage'] as num?) ?? 0).toDouble(),
      promotionPosts: (json['promotion_posts'] as int?) ?? 0,
    );
  }
}