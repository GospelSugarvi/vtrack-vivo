import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Custom exception classes for different error types
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  NetworkException({String? message, dynamic originalError})
    : super(
        message ?? 'Koneksi internet terputus. Periksa koneksi Anda.',
        code: 'NETWORK_ERROR',
        originalError: originalError,
      );
}

class TimeoutException extends AppException {
  TimeoutException({String? message, dynamic originalError})
    : super(
        message ?? 'Waktu request habis. Silakan coba lagi.',
        code: 'TIMEOUT_ERROR',
        originalError: originalError,
      );
}

class ValidationException extends AppException {
  ValidationException({required String message, dynamic originalError})
    : super(message, code: 'VALIDATION_ERROR', originalError: originalError);
}

class PermissionException extends AppException {
  PermissionException({String? message, dynamic originalError})
    : super(
        message ?? 'Anda tidak memiliki izin untuk mengakses data ini.',
        code: 'PERMISSION_ERROR',
        originalError: originalError,
      );
}

class DuplicateDataException extends AppException {
  DuplicateDataException({String? message, dynamic originalError})
    : super(
        message ?? 'Data sudah ada di database.',
        code: 'DUPLICATE_ERROR',
        originalError: originalError,
      );
}

class NotFoundException extends AppException {
  NotFoundException({String? message, dynamic originalError})
    : super(
        message ?? 'Data tidak ditemukan.',
        code: 'NOT_FOUND_ERROR',
        originalError: originalError,
      );
}

class SessionExpiredException extends AppException {
  SessionExpiredException({String? message, dynamic originalError})
    : super(
        message ?? 'Sesi login telah habis. Silakan login kembali.',
        code: 'SESSION_EXPIRED',
        originalError: originalError,
      );
}

class ServerException extends AppException {
  ServerException({String? message, dynamic originalError})
    : super(
        message ?? 'Terjadi kesalahan pada server. Silakan coba lagi nanti.',
        code: 'SERVER_ERROR',
        originalError: originalError,
      );
}

/// Error handler utility class
class ErrorHandler {
  static void _logToTerminal(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
  }) {
    if (!kDebugMode) return;

    debugPrint('========== APP ERROR START ==========');
    if (context != null && context.isNotEmpty) {
      debugPrint('Context : $context');
    }
    debugPrint('Type    : ${error.runtimeType}');

    if (error is PostgrestException) {
      debugPrint('Code    : ${error.code}');
      debugPrint('Message : ${error.message}');
      if ((error.details ?? '').toString().isNotEmpty) {
        debugPrint('Details : ${error.details}');
      }
      if ((error.hint ?? '').toString().isNotEmpty) {
        debugPrint('Hint    : ${error.hint}');
      }
    } else {
      debugPrint('Message : $error');
    }

    if (stackTrace != null) {
      debugPrint('Stack   : $stackTrace');
    }
    debugPrint('=========== APP ERROR END ===========');
  }

  /// Handle any error and return user-friendly message
  static AppException handleError(
    dynamic error, {
    String? context,
    StackTrace? stackTrace,
  }) {
    _logToTerminal(error, context: context, stackTrace: stackTrace);

    // Handle SocketException (no internet)
    if (error is SocketException || error is HttpException) {
      return NetworkException(originalError: error);
    }

    // Handle Timeout
    if (error is TimeoutException) {
      return TimeoutException(originalError: error);
    }

    // Handle Supabase errors
    if (error is PostgrestException) {
      return _handleSupabaseError(error);
    }

    // Handle Auth errors
    if (error is AuthException) {
      return _handleAuthError(error);
    }

    // Handle string errors (from Supabase sometimes)
    if (error is String) {
      return _handleStringError(error);
    }

    // Default unknown error
    return AppException(
      context != null
          ? 'Terjadi kesalahan: $error'
          : 'Terjadi kesalahan yang tidak diketahui.',
      code: 'UNKNOWN_ERROR',
      originalError: error,
    );
  }

  static AppException _handleSupabaseError(PostgrestException error) {
    final code = error.code;
    final message = error.message;
    final details = (error.details ?? '').toString();
    final hint = (error.hint ?? '').toString();

    switch (code) {
      case '23505': // Unique violation
        return DuplicateDataException(
          message: 'Data sudah ada di database.',
          originalError: error,
        );
      case '42501': // Permission denied (RLS)
        return PermissionException(
          message: 'Anda tidak memiliki izin untuk melakukan operasi ini.',
          originalError: error,
        );
      case 'PGRST116': // Not found
        return NotFoundException(
          message: 'Data yang dicari tidak ditemukan.',
          originalError: error,
        );
      case 'PGRST301': // JWT expired
        return SessionExpiredException(originalError: error);
      case '28P01': // Invalid password
        return ValidationException(
          message: 'Password tidak valid.',
          originalError: error,
        );
      case '42703': // Undefined column
        return ServerException(
          message:
              'Struktur database belum sinkron (kolom belum ada). '
              'Jalankan migrasi terbaru Sell Out, lalu coba lagi. '
              '[$code] ${message.isNotEmpty ? message : ''} ${hint.isNotEmpty ? 'Hint: $hint' : ''}',
          originalError: error,
        );
      default:
        if (message.contains('timeout') || message.contains('Time limit')) {
          return TimeoutException(originalError: error);
        }
        if (message.contains('permission') || message.contains('RLS')) {
          return PermissionException(originalError: error);
        }
        return ServerException(
          message:
              'Error database${code != null ? ' [$code]' : ''}: $message'
              '${details.isNotEmpty ? ' | Details: $details' : ''}'
              '${hint.isNotEmpty ? ' | Hint: $hint' : ''}',
          originalError: error,
        );
    }
  }

  static AppException _handleAuthError(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('expired') || message.contains('jwt')) {
      return SessionExpiredException(originalError: error);
    }
    if (message.contains('invalid') || message.contains('credentials')) {
      return ValidationException(
        message: 'Email atau password salah.',
        originalError: error,
      );
    }
    if (message.contains('network') || message.contains('connection')) {
      return NetworkException(originalError: error);
    }

    return AppException(
      'Error autentikasi: ${error.message}',
      code: 'AUTH_ERROR',
      originalError: error,
    );
  }

  static AppException _handleStringError(String error) {
    final lowerError = error.toLowerCase();

    if (lowerError.contains('23505') || lowerError.contains('unique')) {
      return DuplicateDataException(originalError: error);
    }
    if (lowerError.contains('permission') || lowerError.contains('rls')) {
      return PermissionException(originalError: error);
    }
    if (lowerError.contains('timeout') || lowerError.contains('time limit')) {
      return TimeoutException(originalError: error);
    }
    if (lowerError.contains('not found') ||
        lowerError.contains('tidak ditemukan')) {
      return NotFoundException(originalError: error);
    }

    return AppException(error, code: 'STRING_ERROR', originalError: error);
  }

  /// Show error dialog based on exception type
  static void showErrorDialog(
    BuildContext context,
    AppException exception, {
    VoidCallback? onRetry,
  }) {
    String title;
    IconData icon;
    Color color;

    switch (exception.code) {
      case 'NETWORK_ERROR':
        title = 'Koneksi Terputus';
        icon = Icons.wifi_off;
        color = Colors.orange;
        break;
      case 'TIMEOUT_ERROR':
        title = 'Waktu Habis';
        icon = Icons.timer_off;
        color = Colors.orange;
        break;
      case 'VALIDATION_ERROR':
        title = 'Data Tidak Valid';
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      case 'PERMISSION_ERROR':
        title = 'Akses Ditolak';
        icon = Icons.block;
        color = Colors.red;
        break;
      case 'DUPLICATE_ERROR':
        title = 'Data Sudah Ada';
        icon = Icons.content_copy;
        color = Colors.orange;
        break;
      case 'NOT_FOUND_ERROR':
        title = 'Data Tidak Ditemukan';
        icon = Icons.search_off;
        color = Colors.grey;
        break;
      case 'SESSION_EXPIRED':
        title = 'Sesi Berakhir';
        icon = Icons.logout;
        color = Colors.purple;
        break;
      case 'SERVER_ERROR':
        title = 'Error Server';
        icon = Icons.cloud_off;
        color = Colors.red;
        break;
      default:
        title = 'Terjadi Kesalahan';
        icon = Icons.error;
        color = Colors.red;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: color),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              exception.message,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          if (onRetry != null &&
              (exception.code == 'NETWORK_ERROR' ||
                  exception.code == 'TIMEOUT_ERROR'))
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onRetry();
              },
              child: const Text('Coba Lagi'),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show snackbar for less critical errors
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'TUTUP',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  /// Show success snackbar
  static void showSuccessSnackBar(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Execute function with proper error handling
  static Future<T?> executeWithErrorHandling<T>({
    required BuildContext context,
    required Future<T> Function() operation,
    String? loadingMessage,
    String? successMessage,
    bool showLoading = true,
    bool showSuccess = false,
    VoidCallback? onRetry,
  }) async {
    if (showLoading) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text(loadingMessage ?? 'Memproses...'),
            ],
          ),
        ),
      );
    }

    try {
      final result = await operation().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(),
      );

      if (showLoading && context.mounted) {
        Navigator.of(context).pop();
      }

      if (showSuccess && successMessage != null && context.mounted) {
        showSuccessSnackBar(context, successMessage);
      }

      return result;
    } catch (e) {
      if (showLoading && context.mounted) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        final appException = handleError(e);
        showErrorDialog(context, appException, onRetry: onRetry);
      }

      return null;
    }
  }
}

/// Extension for easier error handling
extension ErrorHandlingExtension on BuildContext {
  void showError(String message) {
    ErrorHandler.showErrorSnackBar(this, message);
  }

  void showSuccess(String message) {
    ErrorHandler.showSuccessSnackBar(this, message);
  }
}
