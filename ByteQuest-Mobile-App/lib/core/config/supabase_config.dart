import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Configuration
/// Centralized configuration for Supabase initialization and client access
class SupabaseConfig {
  static const _runtimeUrl = String.fromEnvironment('BQ_SUPABASE_URL');
  static const _runtimeAnonKey = String.fromEnvironment('BQ_SUPABASE_ANON_KEY');

  // Private constructor to prevent instantiation
  SupabaseConfig._();

  // Singleton instance
  static final SupabaseConfig _instance = SupabaseConfig._();
  static SupabaseConfig get instance => _instance;

  // Supabase client getter
  static SupabaseClient get client => Supabase.instance.client;

  // Current user getter
  static User? get currentUser => client.auth.currentUser;

  // Current user ID getter
  static String? get currentUserId => currentUser?.id;

  // Check if user is logged in
  static bool get isLoggedIn => currentUser != null;

  /// Initialize Supabase
  /// Call this before runApp() in main.dart
  static Future<void> initialize() async {
    try {
      // Load environment variables
      await dotenv.load(fileName: '.env');

      // A build-time override lets Android emulators and isolated QA builds
      // use an authorized local backend without rewriting the ignored .env.
      final supabaseUrl =
          _runtimeUrl.isNotEmpty ? _runtimeUrl : dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = _runtimeAnonKey.isNotEmpty
          ? _runtimeAnonKey
          : dotenv.env['SUPABASE_ANON_KEY'];

      // Validate credentials
      if (supabaseUrl == null || supabaseUrl.isEmpty) {
        throw Exception('Supabase URL is not configured');
      }

      if (supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
        throw Exception('Supabase client key is not configured');
      }

      // Initialize Supabase with session persistence (enabled by default)
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          // Auto-refresh tokens before they expire (enabled by default)
          autoRefreshToken: true,
          // Session persistence is enabled by default in Supabase Flutter
        ),
      );

      debugPrint('✅ Supabase initialized successfully');
    } catch (e) {
      debugPrint('❌ Supabase initialization error: $e');
      rethrow;
    }
  }

  /// Get auth state changes stream
  static Stream<AuthState> get authStateChanges {
    return client.auth.onAuthStateChange;
  }

  /// Resolve mission ID to database UUID
  static Future<String> resolveMissionUuid(String idOrCode) async {
    if (RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(idOrCode)) {
      return idOrCode;
    }

    try {
      // 1. Try exact match
      var response = await client
          .from('missions')
          .select('id')
          .eq('mission_code', idOrCode)
          .maybeSingle();

      if (response != null && response['id'] != null) {
        return response['id'] as String;
      }

      // 2. Try lowercase with underscores
      final codeLower = idOrCode.toLowerCase().replaceAll('-', '_');
      response = await client
          .from('missions')
          .select('id')
          .eq('mission_code', codeLower)
          .maybeSingle();

      if (response != null && response['id'] != null) {
        return response['id'] as String;
      }

      // 3. Try uppercase with dashes
      final codeUpper = idOrCode.toUpperCase().replaceAll('_', '-');
      response = await client
          .from('missions')
          .select('id')
          .eq('mission_code', codeUpper)
          .maybeSingle();

      if (response != null && response['id'] != null) {
        return response['id'] as String;
      }
    } catch (e) {
      debugPrint('❌ Error resolving mission UUID for $idOrCode: $e');
    }
    return idOrCode; // Fallback
  }

  /// Resolve COC ID to database UUID
  static Future<String> resolveCocUuid(String idOrCode) async {
    if (RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(idOrCode)) {
      return idOrCode;
    }

    try {
      // 1. Try exact match
      var response = await client
          .from('coc_modules')
          .select('id')
          .eq('coc_code', idOrCode)
          .maybeSingle();

      if (response != null && response['id'] != null) {
        return response['id'] as String;
      }

      // 2. Try lowercase
      final codeLower = idOrCode.toLowerCase();
      response = await client
          .from('coc_modules')
          .select('id')
          .eq('coc_code', codeLower)
          .maybeSingle();

      if (response != null && response['id'] != null) {
        return response['id'] as String;
      }
    } catch (e) {
      debugPrint('❌ Error resolving COC UUID for $idOrCode: $e');
    }
    return idOrCode; // Fallback
  }

  /// Resolve database UUID to local ID (e.g. 'coc1_m1')
  static Future<String> resolveLocalId(String uuid) async {
    if (!RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(uuid)) {
      return uuid;
    }

    try {
      final response = await client
          .from('missions')
          .select('mission_code')
          .eq('id', uuid)
          .maybeSingle();

      if (response != null && response['mission_code'] != null) {
        return (response['mission_code'] as String)
            .toLowerCase()
            .replaceAll('-', '_');
      }
    } catch (e) {
      debugPrint('❌ Error resolving local ID for $uuid: $e');
    }
    return uuid; // Fallback
  }
}

/// Convenience getter for Supabase client
SupabaseClient get supabase => SupabaseConfig.client;
