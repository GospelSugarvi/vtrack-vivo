import {
  formatRupiahShort,
  formatUnitCount,
  preferredDisplayName,
  remainingValue,
  safeString,
  toFiniteNumber,
} from "./shared.ts";

export async function buildSaleContext(supabaseAdmin: any, saleRow: Record<string, unknown>) {
  const [promotorResult, storeResult, variantResult] = await Promise.all([
    supabaseAdmin
      .from("users")
      .select("full_name, nickname, area, role, promotor_type, promotor_status, personal_bonus_target")
      .eq("id", saleRow.promotor_id)
      .maybeSingle(),
    supabaseAdmin
      .from("stores")
      .select("store_name, area, grade, address")
      .eq("id", saleRow.store_id)
      .maybeSingle(),
    supabaseAdmin
      .from("product_variants")
      .select("product_id, ram_rom, color")
      .eq("id", saleRow.variant_id)
      .maybeSingle(),
  ]);

  if (promotorResult.error) throw promotorResult.error;
  if (storeResult.error) throw storeResult.error;
  if (variantResult.error) throw variantResult.error;

  const promotorRow = (promotorResult.data ?? {}) as Record<string, unknown>;
  const storeRow = (storeResult.data ?? {}) as Record<string, unknown>;
  const variantRow = (variantResult.data ?? {}) as Record<string, unknown>;

  const productResult = await supabaseAdmin
    .from("products")
    .select("series, model_name, is_focus")
    .eq("id", variantRow.product_id)
    .maybeSingle();

  if (productResult.error) throw productResult.error;

  const hspResult = await supabaseAdmin
    .from("hierarchy_sator_promotor")
    .select("sator_id")
    .eq("promotor_id", saleRow.promotor_id)
    .eq("active", true)
    .maybeSingle();
  if (hspResult.error) throw hspResult.error;

  const satorId = safeString(hspResult.data?.sator_id);
  let satorRow: Record<string, unknown> = {};
  let spvRow: Record<string, unknown> = {};
  if (satorId) {
    const satorResult = await supabaseAdmin
      .from("users")
      .select("full_name, nickname, area, role")
      .eq("id", satorId)
      .maybeSingle();
    if (satorResult.error) throw satorResult.error;
    satorRow = (satorResult.data ?? {}) as Record<string, unknown>;

    const hssResult = await supabaseAdmin
      .from("hierarchy_spv_sator")
      .select("spv_id")
      .eq("sator_id", satorId)
      .eq("active", true)
      .maybeSingle();
    if (hssResult.error) throw hssResult.error;

    const spvId = safeString(hssResult.data?.spv_id);
    if (spvId) {
      const spvResult = await supabaseAdmin
        .from("users")
        .select("full_name, nickname, area, role")
        .eq("id", spvId)
        .maybeSingle();
      if (spvResult.error) throw spvResult.error;
      spvRow = (spvResult.data ?? {}) as Record<string, unknown>;
    }
  }

  const product = (productResult.data ?? {}) as Record<string, unknown>;
  const monthlyTargetResult = await supabaseAdmin.rpc("get_target_dashboard", {
    p_user_id: saleRow.promotor_id,
    p_period_id: null,
  });
  if (monthlyTargetResult.error) throw monthlyTargetResult.error;

  const dailyTargetResult = await supabaseAdmin.rpc("get_daily_target_dashboard", {
    p_user_id: saleRow.promotor_id,
    p_date: saleRow.transaction_date,
  });
  if (dailyTargetResult.error) throw dailyTargetResult.error;

  const bonusSummaryResult = await supabaseAdmin.rpc("get_promotor_bonus_summary", {
    p_promotor_id: saleRow.promotor_id,
    p_start_date: `${safeString(saleRow.transaction_date).slice(0, 7)}-01`,
    p_end_date: saleRow.transaction_date,
  });
  if (bonusSummaryResult.error) throw bonusSummaryResult.error;

  const daySalesResult = await supabaseAdmin
    .from("sales_sell_out")
    .select("id, price_at_transaction, created_at")
    .eq("promotor_id", saleRow.promotor_id)
    .eq("transaction_date", saleRow.transaction_date)
    .is("deleted_at", null)
    .eq("is_chip_sale", false)
    .lte("created_at", saleRow.created_at);

  if (daySalesResult.error) throw daySalesResult.error;

  const daySales = Array.isArray(daySalesResult.data) ? daySalesResult.data : [];
  const salesTodayCount = daySales.length;
  const omzetToday = daySales.reduce((sum, row) => {
    const value = Number(row.price_at_transaction ?? 0);
    return sum + (Number.isNaN(value) ? 0 : value);
  }, 0);
  const isFirstSaleToday = salesTodayCount <= 1;
  const salesMomentumStage = isFirstSaleToday
    ? "opening_sale"
    : salesTodayCount <= 3
    ? "warming_up"
    : "active_run";

  const monthlyTarget = Array.isArray(monthlyTargetResult.data)
    ? (monthlyTargetResult.data[0] ?? {})
    : (monthlyTargetResult.data ?? {});
  const dailyTarget = Array.isArray(dailyTargetResult.data)
    ? (dailyTargetResult.data[0] ?? {})
    : (dailyTargetResult.data ?? {});
  const bonusSummaryPayload = Array.isArray(bonusSummaryResult.data)
    ? (bonusSummaryResult.data[0]?.get_promotor_bonus_summary ??
        bonusSummaryResult.data[0] ??
        {})
    : (bonusSummaryResult.data?.get_promotor_bonus_summary ??
        bonusSummaryResult.data ??
        {});
  const focusDetails = Array.isArray(monthlyTarget?.fokus_details)
    ? monthlyTarget.fokus_details
    : [];
  const topFocusTargets = focusDetails.slice(0, 3).map((item: Record<string, unknown>) => ({
    bundle_name: safeString(item.bundle_name),
    target_qty: toFiniteNumber(item.target_qty),
    actual_qty: toFiniteNumber(item.actual_qty),
    remaining_qty: remainingValue(item.target_qty, item.actual_qty),
    achievement_pct: toFiniteNumber(item.achievement_pct),
  }));

  const monthlyTargetOmzet = toFiniteNumber(monthlyTarget.target_omzet);
  const monthlyActualOmzet = toFiniteNumber(monthlyTarget.actual_omzet);
  const monthlyTargetFocusTotal = toFiniteNumber(monthlyTarget.target_fokus_total);
  const monthlyActualFocusTotal = toFiniteNumber(monthlyTarget.actual_fokus_total);
  const targetDailyAllType = toFiniteNumber(dailyTarget.target_daily_all_type);
  const actualDailyAllType = toFiniteNumber(dailyTarget.actual_daily_all_type);
  const targetWeeklyAllType = toFiniteNumber(dailyTarget.target_weekly_all_type);
  const actualWeeklyAllType = toFiniteNumber(dailyTarget.actual_weekly_all_type);
  const targetDailyFocus = toFiniteNumber(dailyTarget.target_daily_focus);
  const actualDailyFocus = toFiniteNumber(dailyTarget.actual_daily_focus);
  const targetWeeklyFocus = toFiniteNumber(dailyTarget.target_weekly_focus);
  const actualWeeklyFocus = toFiniteNumber(dailyTarget.actual_weekly_focus);
  const bonusTotalSales = toFiniteNumber(bonusSummaryPayload.total_sales);
  const bonusTotalRevenue = toFiniteNumber(bonusSummaryPayload.total_revenue);
  const bonusTotalBonus = toFiniteNumber(bonusSummaryPayload.total_bonus);
  const personalBonusTarget = toFiniteNumber(promotorRow.personal_bonus_target);

  return {
    saleContext: {
      promotor_name: safeString(promotorRow.full_name) || "Promotor",
      promotor_display_name: preferredDisplayName(promotorRow, "Promotor"),
      promotor_area: safeString(promotorRow.area),
      promotor_role: safeString(promotorRow.role),
      promotor_type: safeString(promotorRow.promotor_type),
      promotor_status: safeString(promotorRow.promotor_status),
      promotor_personal_bonus_target: personalBonusTarget,
      store_name: safeString(storeRow.store_name) || "Toko",
      store_area: safeString(storeRow.area),
      store_grade: safeString(storeRow.grade),
      store_address: safeString(storeRow.address),
      sator_name: preferredDisplayName(satorRow, ""),
      sator_role: safeString(satorRow.role),
      spv_name: preferredDisplayName(spvRow, ""),
      spv_role: safeString(spvRow.role),
      product_name: [safeString(product.series), safeString(product.model_name)]
        .filter(Boolean)
        .join(" "),
      variant_name: [safeString(variantRow.ram_rom), safeString(variantRow.color)]
        .filter(Boolean)
        .join(" "),
      price: saleRow.price_at_transaction,
      price_formatted: formatRupiahShort(saleRow.price_at_transaction),
      payment_method: saleRow.payment_method,
      leasing_provider: saleRow.leasing_provider,
      customer_type: saleRow.customer_type,
      notes: saleRow.notes,
      is_focus: product.is_focus === true,
      transaction_date: saleRow.transaction_date,
      sales_today_count: salesTodayCount,
      omzet_today: omzetToday,
      omzet_today_formatted: formatRupiahShort(omzetToday),
      is_first_sale_today: isFirstSaleToday,
      sales_momentum_stage: salesMomentumStage,
      target_period_name: safeString(monthlyTarget.period_name),
      target_period_start: safeString(monthlyTarget.start_date),
      target_period_end: safeString(monthlyTarget.end_date),
      monthly_target_omzet: monthlyTargetOmzet,
      monthly_target_omzet_formatted: formatRupiahShort(monthlyTargetOmzet),
      monthly_actual_omzet: monthlyActualOmzet,
      monthly_actual_omzet_formatted: formatRupiahShort(monthlyActualOmzet),
      monthly_remaining_omzet: remainingValue(monthlyTargetOmzet, monthlyActualOmzet),
      monthly_remaining_omzet_formatted: formatRupiahShort(
        remainingValue(monthlyTargetOmzet, monthlyActualOmzet),
      ),
      monthly_achievement_omzet_pct: toFiniteNumber(monthlyTarget.achievement_omzet_pct),
      monthly_target_focus_total: monthlyTargetFocusTotal,
      monthly_target_focus_total_formatted: formatUnitCount(monthlyTargetFocusTotal),
      monthly_actual_focus_total: monthlyActualFocusTotal,
      monthly_actual_focus_total_formatted: formatUnitCount(monthlyActualFocusTotal),
      monthly_remaining_focus_units: remainingValue(
        monthlyTargetFocusTotal,
        monthlyActualFocusTotal,
      ),
      monthly_remaining_focus_units_formatted: formatUnitCount(
        remainingValue(monthlyTargetFocusTotal, monthlyActualFocusTotal),
      ),
      monthly_achievement_focus_pct: toFiniteNumber(monthlyTarget.achievement_fokus_pct),
      monthly_time_gone_pct: toFiniteNumber(monthlyTarget.time_gone_pct),
      monthly_status_omzet: safeString(monthlyTarget.status_omzet),
      monthly_status_fokus: safeString(monthlyTarget.status_fokus),
      monthly_warning_omzet: monthlyTarget.warning_omzet === true,
      monthly_warning_fokus: monthlyTarget.warning_fokus === true,
      monthly_focus_targets: topFocusTargets,
      daily_target_period_name: safeString(dailyTarget.period_name),
      active_week_number: toFiniteNumber(dailyTarget.active_week_number),
      working_days_this_week: toFiniteNumber(dailyTarget.working_days),
      target_daily_all_type: targetDailyAllType,
      target_daily_all_type_formatted: formatRupiahShort(targetDailyAllType),
      actual_daily_all_type: actualDailyAllType,
      actual_daily_all_type_formatted: formatRupiahShort(actualDailyAllType),
      remaining_daily_all_type: remainingValue(targetDailyAllType, actualDailyAllType),
      remaining_daily_all_type_formatted: formatRupiahShort(
        remainingValue(targetDailyAllType, actualDailyAllType),
      ),
      achievement_daily_all_type_pct: toFiniteNumber(dailyTarget.achievement_daily_all_type_pct),
      target_weekly_all_type: targetWeeklyAllType,
      target_weekly_all_type_formatted: formatRupiahShort(targetWeeklyAllType),
      actual_weekly_all_type: actualWeeklyAllType,
      actual_weekly_all_type_formatted: formatRupiahShort(actualWeeklyAllType),
      remaining_weekly_all_type: remainingValue(targetWeeklyAllType, actualWeeklyAllType),
      remaining_weekly_all_type_formatted: formatRupiahShort(
        remainingValue(targetWeeklyAllType, actualWeeklyAllType),
      ),
      achievement_weekly_all_type_pct: toFiniteNumber(dailyTarget.achievement_weekly_all_type_pct),
      target_daily_focus: targetDailyFocus,
      target_daily_focus_formatted: formatUnitCount(targetDailyFocus),
      actual_daily_focus: actualDailyFocus,
      actual_daily_focus_formatted: formatUnitCount(actualDailyFocus),
      remaining_daily_focus_units: remainingValue(targetDailyFocus, actualDailyFocus),
      remaining_daily_focus_units_formatted: formatUnitCount(
        remainingValue(targetDailyFocus, actualDailyFocus),
      ),
      achievement_daily_focus_pct: toFiniteNumber(dailyTarget.achievement_daily_focus_pct),
      target_weekly_focus: targetWeeklyFocus,
      target_weekly_focus_formatted: formatUnitCount(targetWeeklyFocus),
      actual_weekly_focus: actualWeeklyFocus,
      actual_weekly_focus_formatted: formatUnitCount(actualWeeklyFocus),
      remaining_weekly_focus_units: remainingValue(targetWeeklyFocus, actualWeeklyFocus),
      remaining_weekly_focus_units_formatted: formatUnitCount(
        remainingValue(targetWeeklyFocus, actualWeeklyFocus),
      ),
      achievement_weekly_focus_pct: toFiniteNumber(dailyTarget.achievement_weekly_focus_pct),
      bonus_period_start: safeString(bonusSummaryPayload.period_start),
      bonus_period_end: safeString(bonusSummaryPayload.period_end),
      bonus_total_sales: bonusTotalSales,
      bonus_total_revenue: bonusTotalRevenue,
      bonus_total_revenue_formatted: formatRupiahShort(bonusTotalRevenue),
      bonus_total_bonus: bonusTotalBonus,
      bonus_total_bonus_formatted: formatRupiahShort(bonusTotalBonus),
      bonus_remaining_to_personal_target: remainingValue(personalBonusTarget, bonusTotalBonus),
      bonus_remaining_to_personal_target_formatted: formatRupiahShort(
        remainingValue(personalBonusTarget, bonusTotalBonus),
      ),
      bonus_event_count: toFiniteNumber(bonusSummaryPayload.event_count),
      bonus_by_type: bonusSummaryPayload.by_bonus_type ?? {},
      metric_notes: {
        omzet_unit: "rupiah",
        focus_unit: "unit",
        daily_all_type_is_omzet: true,
        weekly_all_type_is_omzet: true,
        monthly_focus_is_unit: true,
        daily_focus_is_unit: true,
        weekly_focus_is_unit: true,
        remaining_formula: "remaining = max(target - actual, 0)",
        use_formatted_fields_for_text: true,
      },
    },
    promotorDisplayName: preferredDisplayName(promotorRow, "Promotor"),
  };
}

export async function buildActorReplyContext(
  supabaseAdmin: any,
  userId: string,
  referenceDate: string,
  saleOwnerId: string,
) {
  const { data: actorRow, error: actorError } = await supabaseAdmin
    .from("users")
    .select("full_name, nickname, area, role, promotor_type, promotor_status, personal_bonus_target")
    .eq("id", userId)
    .maybeSingle();

  if (actorError) throw actorError;

  const actor = (actorRow ?? {}) as Record<string, unknown>;
  const actorRole = safeString(actor.role);
  const actorDisplayName = preferredDisplayName(actor, "User");
  const actorContext: Record<string, unknown> = {
    actor_user_id: userId,
    actor_display_name: actorDisplayName,
    actor_full_name: safeString(actor.full_name),
    actor_role: actorRole,
    actor_area: safeString(actor.area),
    actor_promotor_type: safeString(actor.promotor_type),
    actor_promotor_status: safeString(actor.promotor_status),
    actor_is_sale_owner: userId === saleOwnerId,
  };

  if (actorRole !== "promotor") {
    return actorContext;
  }

  const monthlyTargetResult = await supabaseAdmin.rpc("get_target_dashboard", {
    p_user_id: userId,
    p_period_id: null,
  });
  if (monthlyTargetResult.error) throw monthlyTargetResult.error;

  const dailyTargetResult = await supabaseAdmin.rpc("get_daily_target_dashboard", {
    p_user_id: userId,
    p_date: referenceDate,
  });
  if (dailyTargetResult.error) throw dailyTargetResult.error;

  const bonusSummaryResult = await supabaseAdmin.rpc("get_promotor_bonus_summary", {
    p_promotor_id: userId,
    p_start_date: `${safeString(referenceDate).slice(0, 7)}-01`,
    p_end_date: referenceDate,
  });
  if (bonusSummaryResult.error) throw bonusSummaryResult.error;

  const monthlyTarget = Array.isArray(monthlyTargetResult.data)
    ? (monthlyTargetResult.data[0] ?? {})
    : (monthlyTargetResult.data ?? {});
  const dailyTarget = Array.isArray(dailyTargetResult.data)
    ? (dailyTargetResult.data[0] ?? {})
    : (dailyTargetResult.data ?? {});
  const bonusSummaryPayload = Array.isArray(bonusSummaryResult.data)
    ? (bonusSummaryResult.data[0]?.get_promotor_bonus_summary ??
        bonusSummaryResult.data[0] ??
        {})
    : (bonusSummaryResult.data?.get_promotor_bonus_summary ??
        bonusSummaryResult.data ??
        {});

  const monthlyTargetOmzet = toFiniteNumber(monthlyTarget.target_omzet);
  const monthlyActualOmzet = toFiniteNumber(monthlyTarget.actual_omzet);
  const monthlyTargetFocusTotal = toFiniteNumber(monthlyTarget.target_fokus_total);
  const monthlyActualFocusTotal = toFiniteNumber(monthlyTarget.actual_fokus_total);
  const bonusTotalBonus = toFiniteNumber(bonusSummaryPayload.total_bonus);
  const personalBonusTarget = toFiniteNumber(actor.personal_bonus_target);

  return {
    ...actorContext,
    actor_target_period_name: safeString(monthlyTarget.period_name),
    actor_monthly_target_omzet_formatted: formatRupiahShort(monthlyTargetOmzet),
    actor_monthly_actual_omzet_formatted: formatRupiahShort(monthlyActualOmzet),
    actor_monthly_remaining_omzet_formatted: formatRupiahShort(
      remainingValue(monthlyTargetOmzet, monthlyActualOmzet),
    ),
    actor_monthly_target_focus_total_formatted: formatUnitCount(monthlyTargetFocusTotal),
    actor_monthly_actual_focus_total_formatted: formatUnitCount(monthlyActualFocusTotal),
    actor_monthly_remaining_focus_units_formatted: formatUnitCount(
      remainingValue(monthlyTargetFocusTotal, monthlyActualFocusTotal),
    ),
    actor_target_daily_focus_formatted: formatUnitCount(dailyTarget.target_daily_focus),
    actor_actual_daily_focus_formatted: formatUnitCount(dailyTarget.actual_daily_focus),
    actor_remaining_daily_focus_units_formatted: formatUnitCount(
      remainingValue(dailyTarget.target_daily_focus, dailyTarget.actual_daily_focus),
    ),
    actor_target_weekly_focus_formatted: formatUnitCount(dailyTarget.target_weekly_focus),
    actor_actual_weekly_focus_formatted: formatUnitCount(dailyTarget.actual_weekly_focus),
    actor_remaining_weekly_focus_units_formatted: formatUnitCount(
      remainingValue(dailyTarget.target_weekly_focus, dailyTarget.actual_weekly_focus),
    ),
    actor_bonus_period_start: safeString(bonusSummaryPayload.period_start),
    actor_bonus_period_end: safeString(bonusSummaryPayload.period_end),
    actor_bonus_total_bonus_formatted: formatRupiahShort(bonusTotalBonus),
    actor_bonus_remaining_to_personal_target_formatted: formatRupiahShort(
      remainingValue(personalBonusTarget, bonusTotalBonus),
    ),
  };
}
