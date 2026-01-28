import 'package:flutter/foundation.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/logic/mappers/update_mapper.dart';

class ProfileController extends ChangeNotifier {
  final AuthService _authService;
  final UpdateService _updateService;

  ProfileController({
    required AuthService authService,
    required UpdateService updateService,
  }) : _authService = authService,
       _updateService = updateService {
    _authService.addListener(notifyListeners);
    _updateService.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _authService.removeListener(notifyListeners);
    _updateService.removeListener(notifyListeners);
    super.dispose();
  }

  // Auth delegation
  bool get isAuthenticated => _authService.isAuthenticated;
  Map<String, dynamic>? get currentUser => _authService.currentUser;
  Future<void> signOut() => _authService.signOut();

  // Update delegation
  UpdateStatus get updateStatus => _updateService.status;
  String? get latestDownloadUrl => _updateService.latestDownloadUrl;
  UpdateUIDescriptor get updateUI => UpdateMapper.map(_updateService.status);
}
