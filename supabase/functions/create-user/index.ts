// Supabase Edge Function: create-user
// This function creates new users with admin privileges
// Deploy with: supabase functions deploy create-user --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get the authorization header to verify admin
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing authorization header");
    }

    // Create Supabase client with service role
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SERVICE_ROLE_KEY") ?? "",
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    );

    // Verify the requesting user is an admin
    const token = authHeader.replace("Bearer ", "");
    const { data: { user: requestingUser }, error: authError } = await supabaseAdmin.auth.getUser(token);

    if (authError || !requestingUser) {
      throw new Error("Unauthorized");
    }

    // Check if requesting user is admin
    const { data: adminCheck } = await supabaseAdmin
      .from("users")
      .select("role")
      .eq("id", requestingUser.id)
      .single();

    if (!adminCheck || adminCheck.role !== "admin") {
      throw new Error("Only admins can create users");
    }

    // Parse request body
    const { email, password, full_name, nickname, role, area, supervisor_id, store_id, promotor_status } = await req.json();

    if (!email || !password || !full_name) {
      throw new Error("Email, password, and full_name are required");
    }

    // Create auth user (automatically confirmed)
    const { data: authData, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (createError) {
      throw new Error(`Failed to create auth user: ${createError.message}`);
    }

    if (!authData.user) {
      throw new Error("Failed to create user");
    }

    const newUserId = authData.user.id;

    // Create user profile in users table
    const { error: profileError } = await supabaseAdmin.from("users").insert({
      id: newUserId,
      email,
      full_name,
      nickname: nickname || null,
      username: full_name.toLowerCase().replace(/\s/g, '_'),
      role: role || "promotor",
      area: area || null,
      promotor_status: role === 'promotor' ? (promotor_status || 'training') : null,
      status: "active",
    });

    if (profileError) {
      // Rollback: delete auth user if profile creation fails
      await supabaseAdmin.auth.admin.deleteUser(newUserId);
      throw new Error(`Failed to create user profile: ${profileError.message}`);
    }

    // Create hierarchy record if supervisor_id is provided
    if (supervisor_id && ['promotor', 'sator', 'spv'].includes(role)) {
      let hierarchyTable = '';
      let subordinateField = '';
      let supervisorField = '';

      switch (role) {
        case 'promotor':
          hierarchyTable = 'hierarchy_sator_promotor';
          subordinateField = 'promotor_id';
          supervisorField = 'sator_id';
          break;
        case 'sator':
          hierarchyTable = 'hierarchy_spv_sator';
          subordinateField = 'sator_id';
          supervisorField = 'spv_id';
          break;
        case 'spv':
          hierarchyTable = 'hierarchy_manager_spv';
          subordinateField = 'spv_id';
          supervisorField = 'manager_id';
          break;
      }

      if (hierarchyTable) {
        const hierarchyRecord = {
          [subordinateField]: newUserId,
          [supervisorField]: supervisor_id,
          active: true,
        };

        const { error: hierarchyError } = await supabaseAdmin.from(hierarchyTable).insert(hierarchyRecord);

        if (hierarchyError) {
          console.error("Failed to create hierarchy:", hierarchyError.message);
        }
      }
    }

    // Create Store Assignment if store_id provided (for promotor)
    if (role === 'promotor' && store_id) {
      const { error: assignmentError } = await supabaseAdmin.from('assignments_promotor_store').insert({
        promotor_id: newUserId,
        store_id: store_id,
        status: 'verified',
      });

      if (assignmentError) {
        console.error("Failed to assign store:", assignmentError.message);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        user: {
          id: newUserId,
          email,
          full_name,
          role,
        },
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }
});
