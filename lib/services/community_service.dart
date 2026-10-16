import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'auth_service.dart';

class CommunityService {
  CommunityService._();
  static final instance = CommunityService._();

  String get _base => AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '');

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final token = await AuthService.instance.googleIdToken();
    if (token == null) throw Exception('Please sign in again with Google to use the community.');
    return {
      'authorization': 'Bearer $token',
      if (jsonBody) 'content-type': 'application/json',
    };
  }

  Future<dynamic> _request(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    final headers = await _headers(jsonBody: body != null);
    final uri = Uri.parse('$_base$path');
    final response = method == 'POST'
        ? await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 15))
        : await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data is Map ? '${data['error'] ?? 'Community request failed'}' : 'Community request failed');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> posts() async {
    final d = await _request('/community/posts');
    return (d['posts'] as List).cast<Map<String, dynamic>>();
  }
  Future<List<Map<String, dynamic>>> comments(String postId) async {
    final d = await _request('/community/comments?postId=${Uri.encodeQueryComponent(postId)}');
    return (d['comments'] as List).cast<Map<String, dynamic>>();
  }
  Future<void> createPost(String text, {String? movieTitle, String? movieImage, int? rating}) async {
    await _request('/community/posts', method: 'POST', body: {'text': text, 'movieTitle': movieTitle, 'movieImage': movieImage, 'rating': rating});
  }
  Future<void> comment(String postId, String text) async {
    await _request('/community/comments', method: 'POST', body: {'postId': postId, 'text': text});
  }
  Future<void> toggleLike(String postId) async {
    await _request('/community/like', method: 'POST', body: {'postId': postId});
  }
  Future<Map<String, dynamic>> profile(String email) async {
    final d = await _request('/community/profile?email=${Uri.encodeQueryComponent(email)}');
    return (d['profile'] as Map).cast<String, dynamic>();
  }
  Future<List<Map<String, dynamic>>> people() async {
    final d = await _request('/community/people');
    return (d['people'] as List).cast<Map<String, dynamic>>();
  }
}
