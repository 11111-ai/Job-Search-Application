import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- MODELS ----------
class User {
  final String id;
  final String email;
  final String fullName;
  final DateTime? dateOfBirth;
  final String location;
  final DateTime? graduationDate;
  final String graduationInstitution;
  final String transportationMode;
  final String resumeUrl;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    this.dateOfBirth,
    required this.location,
    this.graduationDate,
    required this.graduationInstitution,
    required this.transportationMode,
    required this.resumeUrl,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'full_name': fullName,
        'date_of_birth': dateOfBirth?.toIso8601String(),
        'location': location,
        'graduation_date': graduationDate?.toIso8601String(),
        'graduation_institution': graduationInstitution,
        'transportation_mode': transportationMode,
      };
}

class Job {
  final String id;
  final String title;
  final String company;
  final String location;
  final double? salaryMin;
  final double? salaryMax;
  final String description;
  final String requirements;
  final String jobType;
  final String category;
  final bool isRemote;
  final DateTime postedDate;

  Job({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    this.salaryMin,
    this.salaryMax,
    required this.description,
    required this.requirements,
    required this.jobType,
    required this.category,
    required this.isRemote,
    required this.postedDate,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      company: json['company'] ?? '',
      location: json['location'] ?? '',
      salaryMin: json['salary_min']?.toDouble(),
      salaryMax: json['salary_max']?.toDouble(),
      description: json['description'] ?? '',
      requirements: json['requirements'] ?? '',
      jobType: json['job_type'] ?? 'Full-time',
      category: json['category'] ?? 'General',
      isRemote: json['is_remote'] ?? false,
      postedDate: DateTime.parse(
          json['posted_date'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class JobApplication {
  final String id;
  final String jobId;
  final String userId;
  final String status;
  final DateTime appliedAt;
  final Job job;

  JobApplication({
    required this.id,
    required this.jobId,
    required this.userId,
    required this.status,
    required this.appliedAt,
    required this.job,
  });
}

// ---------- SERVICES ----------
class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8080';
  String? authToken;
  Future<void>? _tokenLoadFuture;

  ApiService() {
    _tokenLoadFuture = _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    authToken = prefs.getString('authToken');
  }

  Future<void> _ensureTokenLoaded() async {
    if (_tokenLoadFuture != null) {
      await _tokenLoadFuture;
      _tokenLoadFuture = null;
    }
  }

  Future<void> _saveToken(String token) async {
    authToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authToken', token);
  }

  Future<bool> isLoggedIn() async {
    await _ensureTokenLoaded();
    if (authToken == null || authToken!.isEmpty) {
      return false;
    }
    
    // Try to fetch user applications to verify token is valid
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/applications/'),
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('Token validation failed: $e');
      return false;
    }
  }

  Future<void> clearToken() async {
    authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
  }

  Future<bool> testConnection() async {
    try {
      print('🔍 Testing connection to $baseUrl');
      final response = await http.get(Uri.parse('$baseUrl/')).timeout(
            Duration(seconds: 5),
          );
      print('✅ Connection test successful: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Connection test failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      print('🔵 Attempting login to: $baseUrl/auth/login');
      print('📧 Email: $email');

      final response = await http
          .post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      )
          .timeout(
        Duration(seconds: 30),
        onTimeout: () {
          print('⏰ Timeout occurred after 30 seconds');
          throw Exception(
              'Connection timeout. Make sure the backend server is running.');
        },
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveToken(data['access_token']);
        print('✅ Login successful');
        return {'success': true, 'user': data['user']};
      } else {
        String message = 'Login failed';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['detail'] is String) {
            message = data['detail'];
          }
        } catch (_) {}
        print('❌ Login failed: $message');
        return {
          'success': false,
          'status': response.statusCode,
          'error': message
        };
      }
    } catch (e) {
      print('🔴 Error occurred: $e');
      return {
        'success': false,
        'status': 0,
        'error': e.toString().contains('timeout') ||
                e.toString().contains('Connection timeout')
            ? 'Connection timeout. Please make sure the backend server is running at $baseUrl'
            : 'Network error: ${e.toString()}'
      };
    }
  }

  Future<Map<String, dynamic>> signup(
      User user, String password, File? resume) async {
    var request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/auth/signup'));

    // Add user data
    request.fields['email'] = user.email;
    request.fields['password'] = password;
    request.fields['full_name'] = user.fullName;
    request.fields['location'] = user.location;
    request.fields['graduation_institution'] = user.graduationInstitution;
    request.fields['transportation_mode'] = user.transportationMode;

    if (user.dateOfBirth != null) {
      request.fields['date_of_birth'] =
          DateFormat('yyyy-MM-dd').format(user.dateOfBirth!);
    }
    if (user.graduationDate != null) {
      request.fields['graduation_date'] =
          DateFormat('yyyy-MM-dd').format(user.graduationDate!);
    }

    // Add resume file if exists
    if (resume != null && !kIsWeb) {
      request.files
          .add(await http.MultipartFile.fromPath('resume', resume.path));
    }

    try {
      final streamedResponse = await request.send().timeout(
        Duration(seconds: 15),
        onTimeout: () {
          throw Exception(
              'Connection timeout. Make sure the backend server is running.');
        },
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveToken(data['access_token']);
        return {'success': true, 'user': data['user']};
      } else {
        String message = 'Signup failed';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['detail'] is String) {
            message = data['detail'];
          }
        } catch (_) {}
        return {
          'success': false,
          'status': response.statusCode,
          'error': message
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString().contains('timeout') ||
                e.toString().contains('Connection timeout')
            ? 'Connection timeout. Please make sure the backend server is running at $baseUrl'
            : 'Network error: ${e.toString()}'
      };
    }
  }

  Future<List<Job>> getJobs({
    String? title,
    String? location,
    String? category,
  }) async {
    final queryParams = <String, String>{};
    if (title != null && title.isNotEmpty) queryParams['title'] = title;
    if (location != null && location.isNotEmpty)
      queryParams['location'] = location;
    if (category != null && category.isNotEmpty)
      queryParams['category'] = category;

    final uri =
        Uri.parse('$baseUrl/jobs/').replace(queryParameters: queryParams);
    try {
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((job) => Job.fromJson(job)).toList();
      }
      return [];
    } catch (e) {
      print('Error loading jobs: $e');
      return [];
    }
  }

  Future<List<Job>> getRecommendedJobs() async {
    await _ensureTokenLoaded();
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/jobs/recommended'),
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((job) => Job.fromJson(job)).toList();
      }
      return [];
    } catch (e) {
      print('Error loading recommended jobs: $e');
      return [];
    }
  }

  Future<List<dynamic>> getApplications() async {
    await _ensureTokenLoaded();
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/applications/'),
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data;
      }
      return [];
    } catch (e) {
      print('Error loading applications: $e');
      return [];
    }
  }

  Future<bool> applyForJob(String jobId) async {
    await _ensureTokenLoaded();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/applications/'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: json.encode({'job_id': jobId}),
          )
          .timeout(Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('Error applying for job: $e');
      return false;
    }
  }
}

// ---------- WIDGETS ----------
class JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;

  const JobCard({
    Key? key,
    required this.job,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.blue.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.2),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.work,
                          color: Colors.blue.shade700, size: 28),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            job.title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            job.company,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.location_on,
                        size: 18, color: Colors.red.shade400),
                    SizedBox(width: 4),
                    Text(
                      job.location,
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                    SizedBox(width: 16),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: job.isRemote
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            job.isRemote ? Icons.home : Icons.business,
                            size: 14,
                            color: job.isRemote
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                          SizedBox(width: 4),
                          Text(
                            job.isRemote ? 'Remote' : 'On-site',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: job.isRemote
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                if (job.salaryMin != null && job.salaryMax != null)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_money,
                            size: 18, color: Colors.purple.shade700),
                        Text(
                          '\$${job.salaryMin!.toInt()} - \$${job.salaryMax!.toInt()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: 12),
                Text(
                  job.description.length > 120
                      ? '${job.description.substring(0, 120)}...'
                      : job.description,
                  style: TextStyle(
                      color: Colors.grey[700], fontSize: 14, height: 1.4),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        job.jobType,
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue.shade700),
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        job.category,
                        style: TextStyle(
                            fontSize: 12, color: Colors.teal.shade700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FilterBottomSheet extends StatefulWidget {
  final Function(Map<String, String>)? onApplyFilters;

  const FilterBottomSheet({Key? key, this.onApplyFilters}) : super(key: key);

  @override
  _FilterBottomSheetState createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  String _selectedJobType = 'Any';
  String _selectedCategory = 'Any';
  bool _remoteOnly = false;

  final List<String> _jobTypes = [
    'Any',
    'Full-time',
    'Part-time',
    'Contract',
    'Internship'
  ];
  final List<String> _categories = [
    'Any',
    'IT',
    'Marketing',
    'Healthcare',
    'Finance',
    'Education'
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter Jobs',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          Text('Job Type', style: TextStyle(fontWeight: FontWeight.w500)),
          DropdownButton<String>(
            value: _selectedJobType,
            isExpanded: true,
            onChanged: (value) {
              setState(() => _selectedJobType = value!);
            },
            items: _jobTypes.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type),
              );
            }).toList(),
          ),
          SizedBox(height: 20),
          Text('Category', style: TextStyle(fontWeight: FontWeight.w500)),
          DropdownButton<String>(
            value: _selectedCategory,
            isExpanded: true,
            onChanged: (value) {
              setState(() => _selectedCategory = value!);
            },
            items: _categories.map((category) {
              return DropdownMenuItem(
                value: category,
                child: Text(category),
              );
            }).toList(),
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Checkbox(
                value: _remoteOnly,
                onChanged: (value) {
                  setState(() => _remoteOnly = value!);
                },
              ),
              Text('Remote Only'),
            ],
          ),
          SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApplyFilters?.call({
                      'job_type':
                          _selectedJobType == 'Any' ? '' : _selectedJobType,
                      'category':
                          _selectedCategory == 'Any' ? '' : _selectedCategory,
                      'is_remote': _remoteOnly.toString(),
                    });
                    Navigator.pop(context);
                  },
                  child: Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- SCREENS ----------
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.purple.shade300],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(Icons.work_outline,
                        size: 80, color: Colors.blue.shade700),
                  ),
                  SizedBox(height: 30),
                  Text(
                    'Welcome Back!',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Login to find your dream job',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(height: 40),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email,
                                  color: Colors.blue.shade700),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.blue.shade700, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!_isValidEmail(value)) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: 20),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon:
                                  Icon(Icons.lock, color: Colors.blue.shade700),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.blue.shade700, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: 30),
                          _isLoading
                              ? CircularProgressIndicator()
                              : Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue.shade600,
                                        Colors.purple.shade400
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      'Login',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SignupScreen()),
                      );
                    },
                    child: Text(
                      'Don\'t have an account? Sign up',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    // Test connection first
    final canConnect = await _apiService.testConnection();
    if (!canConnect) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Cannot connect to server at ${ApiService.baseUrl}. Please make sure the backend is running.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    try {
      final result = await _apiService.login(email, password);
      if (result['success'] == true) {
        // Save user profile data to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final userData = result['user'];
        
        if (userData != null) {
          await prefs.setString('email', userData['email'] ?? email);
          await prefs.setString('fullName', userData['full_name'] ?? '');
          await prefs.setString('location', userData['location'] ?? '');
          await prefs.setString('graduationInstitution', userData['graduation_institution'] ?? '');
          await prefs.setString('transportationMode', userData['transportation_mode'] ?? '');
          
          if (userData['date_of_birth'] != null) {
            await prefs.setString('dateOfBirth', userData['date_of_birth']);
          }
          if (userData['graduation_date'] != null) {
            await prefs.setString('graduationDate', userData['graduation_date']);
          }
        }
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      } else {
        final status = result['status'] as int?;
        final error = (result['error'] as String?) ?? 'Login failed';
        final needsSignup = status == 401 ||
            status == 404 ||
            error.toLowerCase().contains('invalid');

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Login Issue'),
            content: Text(
              needsSignup
                  ? 'No account found for this email. Please sign up first, then log in.'
                  : error,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Close'),
              ),
              if (needsSignup)
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SignupScreen()),
                    );
                  },
                  child: Text('Go to Sign Up'),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error. Please try again.')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

class SignupScreen extends StatefulWidget {
  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _locationController = TextEditingController();
  final _graduationInstitutionController = TextEditingController();
  final _transportationController = TextEditingController();

  DateTime? _dateOfBirth;
  DateTime? _graduationDate;
  File? _resumeFile;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  String? _selectedMajor;
  
  final List<String> _majors = [
    'Computer Science',
    'Information Technology',
    'Software Engineering',
    'Computer Engineering',
    'Data Science',
    'Artificial Intelligence',
    'Cybersecurity',
    'Business Administration',
    'Management',
    'Marketing',
    'Finance',
    'Accounting',
    'Economics',
    'Mechanical Engineering',
    'Electrical Engineering',
    'Civil Engineering',
    'Chemical Engineering',
    'Industrial Engineering',
    'Biomedical Engineering',
    'Aerospace Engineering',
    'Medicine',
    'Nursing',
    'Pharmacy',
    'Dentistry',
    'Biology',
    'Chemistry',
    'Physics',
    'Mathematics',
    'Statistics',
    'Psychology',
    'Sociology',
    'Political Science',
    'International Relations',
    'Law',
    'Education',
    'English Literature',
    'History',
    'Philosophy',
    'Architecture',
    'Graphic Design',
    'Fine Arts',
    'Music',
    'Media Studies',
    'Journalism',
    'Communications',
    'Agriculture',
    'Environmental Science',
    'Geology',
    'Other',
  ];

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade400, Colors.blue.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                SizedBox(height: 20),
                Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Start your job search journey',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                SizedBox(height: 30),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email,
                                color: Colors.purple.shade700),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!_isValidEmail(value)) {
                              return 'Please enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon:
                                Icon(Icons.lock, color: Colors.purple.shade700),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) {
                            if (value == null || value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            if (!value.contains(RegExp(r'[A-Z]'))) {
                              return 'Password must contain at least 1 capital letter';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _fullNameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person,
                                color: Colors.purple.shade700),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) =>
                              value!.isEmpty ? 'Required' : null,
                        ),
                        SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade50,
                          ),
                          child: ListTile(
                            leading:
                                Icon(Icons.cake, color: Colors.purple.shade700),
                            title: Text(_dateOfBirth == null
                                ? 'Select Date of Birth'
                                : 'DOB: ${DateFormat('yyyy-MM-dd').format(_dateOfBirth!)}'),
                            onTap: () => _selectDate(true),
                          ),
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _locationController,
                          decoration: InputDecoration(
                            labelText: 'Location',
                            prefixIcon: Icon(Icons.location_on,
                                color: Colors.purple.shade700),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) =>
                              value!.isEmpty ? 'Required' : null,
                        ),
                        SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade50,
                          ),
                          child: ListTile(
                            leading: Icon(Icons.calendar_today,
                                color: Colors.purple.shade700),
                            title: Text(_graduationDate == null
                                ? 'Select Graduation Date'
                                : 'Graduation: ${DateFormat('yyyy-MM-dd').format(_graduationDate!)}'),
                            onTap: () => _selectDate(false),
                          ),
                        ),
                        SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedMajor,
                          decoration: InputDecoration(
                            labelText: 'Major / Field of Study',
                            prefixIcon: Icon(Icons.school,
                                color: Colors.purple.shade700),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          items: _majors.map((String major) {
                            return DropdownMenuItem<String>(
                              value: major,
                              child: Text(major),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedMajor = newValue;
                              _graduationInstitutionController.text = newValue ?? '';
                            });
                          },
                          validator: (value) =>
                              value == null || value.isEmpty ? 'Please select a major' : null,
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _transportationController,
                          decoration: InputDecoration(
                            labelText: 'Transportation Mode',
                            prefixIcon: Icon(Icons.directions_car,
                                color: Colors.purple.shade700),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) =>
                              value!.isEmpty ? 'Required' : null,
                        ),
                        SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _pickResume,
                          icon: Icon(
                              _resumeFile == null
                                  ? Icons.upload_file
                                  : Icons.check_circle,
                              color: Colors.purple.shade700),
                          label: Text(
                            _resumeFile == null
                                ? 'Upload Resume'
                                : 'Resume Selected',
                            style: TextStyle(color: Colors.purple.shade700),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size(double.infinity, 56),
                            side: BorderSide(color: Colors.purple.shade300),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        SizedBox(height: 30),
                        _isLoading
                            ? Center(child: CircularProgressIndicator())
                            : Container(
                                width: double.infinity,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.purple.shade600,
                                      Colors.blue.shade400
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.purple.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _signup,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'Sign Up',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(bool isBirthDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isBirthDate) {
          _dateOfBirth = picked;
        } else {
          _graduationDate = picked;
        }
      });
    }
  }

  void _pickResume() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _resumeFile = File(file.path));
    }
  }

  void _signup() async {
    if (_formKey.currentState!.validate()) {
      // Validate date of birth and graduation date
      if (_dateOfBirth != null && _graduationDate != null) {
        final age = _graduationDate!.difference(_dateOfBirth!).inDays ~/ 365;
        if (age < 20) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Graduation date must be at least 20 years after date of birth',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          return;
        }
      }
      
      setState(() => _isLoading = true);

      final user = User(
        id: '',
        email: _emailController.text,
        fullName: _fullNameController.text,
        dateOfBirth: _dateOfBirth,
        location: _locationController.text,
        graduationDate: _graduationDate,
        graduationInstitution: _graduationInstitutionController.text,
        transportationMode: _transportationController.text,
        resumeUrl: '',
      );

      try {
        final apiService = ApiService();
        final result = await apiService.signup(
            user, _passwordController.text, _resumeFile);

        if (result['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          final userData = result['user'];

          // Save all user data
          await prefs.setString(
              'email', userData['email'] ?? _emailController.text);
          await prefs.setString(
              'fullName', userData['full_name'] ?? _fullNameController.text);
          await prefs.setString(
              'location', userData['location'] ?? _locationController.text);
          await prefs.setString(
              'graduationInstitution',
              userData['graduation_institution'] ??
                  _graduationInstitutionController.text);
          await prefs.setString(
              'transportationMode',
              userData['transportation_mode'] ??
                  _transportationController.text);

          if (_dateOfBirth != null) {
            await prefs.setString(
                'dateOfBirth', _dateOfBirth!.toIso8601String());
          }
          if (_graduationDate != null) {
            await prefs.setString(
                'graduationDate', _graduationDate!.toIso8601String());
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Signup failed')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error. Please try again.')),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Job> _jobs = [];
  List<Job> _filteredJobs = [];
  List<Job> _recommendedJobs = [];
  bool _isLoading = true;
  bool _showRecommended = true;
  int _currentIndex = 0;
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _loadRecommendedJobs();
  }

  void _loadJobs() async {
    setState(() => _isLoading = true);
    try {
      final jobs = await _apiService.getJobs();
      setState(() {
        _jobs = jobs;
        _filteredJobs = jobs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Failed to load jobs. Please check your connection.')),
      );
    }
  }

  void _loadRecommendedJobs() async {
    try {
      final recommended = await _apiService.getRecommendedJobs();
      setState(() {
        _recommendedJobs = recommended;
      });
    } catch (e) {
      print('Failed to load recommended jobs: $e');
    }
  }

  void _searchJobs(String query) {
    if (query.isEmpty) {
      setState(() => _filteredJobs = _jobs);
    } else {
      setState(() {
        _filteredJobs = _jobs.where((job) {
          return job.title.toLowerCase().contains(query.toLowerCase()) ||
              job.company.toLowerCase().contains(query.toLowerCase()) ||
              job.location.toLowerCase().contains(query.toLowerCase());
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text('Job Search', style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.purple.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.purple.shade400],
              ),
            ),
            padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search jobs...',
                  prefixIcon: Icon(Icons.search, color: Colors.blue.shade700),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.blue.shade700),
                          onPressed: () {
                            _searchController.clear();
                            _searchJobs('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                onChanged: _searchJobs,
              ),
            ),
          ),
          Expanded(
            child: _buildJobsList(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ApplicationsScreen()),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfileScreen()),
            );
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.list_alt), label: 'Applications'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildJobsList() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    if (_filteredJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No jobs found',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView(
      children: [
        // Recommended Jobs Section
        if (_recommendedJobs.isNotEmpty && _searchController.text.isEmpty) ...[
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.shade50, Colors.orange.shade50],
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.star, color: Colors.amber.shade700, size: 28),
                SizedBox(width: 8),
                Text(
                  'Recommended for You',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
          ),
          ..._recommendedJobs.take(5).map((job) => JobCard(
                job: job,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => JobDetailScreen(job: job),
                    ),
                  );
                },
              )),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.purple.shade50],
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.work_outline, color: Colors.blue.shade700, size: 24),
                SizedBox(width: 8),
                Text(
                  'All Available Jobs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_jobs.length} jobs',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // All Jobs List - show all jobs when not searching, filtered jobs when searching
        ...(_searchController.text.isEmpty ? _jobs : _filteredJobs).map((job) => JobCard(
              job: job,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => JobDetailScreen(job: job),
                  ),
                );
              },
            )),
      ],
    );
  }
}

class JobSearchDelegate extends SearchDelegate {
  final List<Job> jobs;

  JobSearchDelegate({required this.jobs});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = jobs.where((job) =>
        job.title.toLowerCase().contains(query.toLowerCase()) ||
        job.company.toLowerCase().contains(query.toLowerCase()) ||
        job.location.toLowerCase().contains(query.toLowerCase()));

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final job = results.elementAt(index);
        return JobCard(
          job: job,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => JobDetailScreen(job: job)),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return buildResults(context);
  }
}

class JobDetailScreen extends StatefulWidget {
  final Job job;

  const JobDetailScreen({Key? key, required this.job}) : super(key: key);

  @override
  _JobDetailScreenState createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  final ApiService _apiService = ApiService();
  bool _isApplying = false;

  Widget _buildInfoChip(
      {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _applyForJob() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apply for Job'),
        content: Text(
            'Are you sure you want to apply for ${widget.job.title} at ${widget.job.company}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isApplying = true);
              try {
                final success = await _apiService.applyForJob(widget.job.id);
                setState(() => _isApplying = false);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Application submitted successfully!')),
                  );
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Failed to apply. You may have already applied.')),
                  );
                }
              } catch (e) {
                setState(() => _isApplying = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Network error. Please try again.')),
                );
              }
            },
            child: Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.job.title,
                style: TextStyle(fontWeight: FontWeight.bold, shadows: [
                  Shadow(color: Colors.black45, blurRadius: 10),
                ]),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade600, Colors.purple.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Icon(Icons.work,
                      size: 80, color: Colors.white.withOpacity(0.3)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade50, Colors.purple.shade50],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.business,
                                color: Colors.blue.shade700, size: 28),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.job.company,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildInfoChip(
                              icon: Icons.location_on,
                              label: widget.job.location,
                              color: Colors.red.shade400,
                            ),
                            _buildInfoChip(
                              icon: widget.job.isRemote
                                  ? Icons.home
                                  : Icons.business,
                              label: widget.job.isRemote ? 'Remote' : 'On-site',
                              color: widget.job.isRemote
                                  ? Colors.green.shade600
                                  : Colors.orange.shade600,
                            ),
                            _buildInfoChip(
                              icon: Icons.work,
                              label: widget.job.jobType,
                              color: Colors.blue.shade600,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  if (widget.job.salaryMin != null &&
                      widget.job.salaryMax != null)
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple.shade100,
                            Colors.purple.shade50
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.purple.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet,
                              color: Colors.purple.shade700, size: 32),
                          SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Salary Range',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              ),
                              Text(
                                '\$${widget.job.salaryMin!.toInt()} - \$${widget.job.salaryMax!.toInt()}',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 30),
                  _buildSectionTitle('Job Description', Icons.description,
                      Colors.blue.shade700),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.job.description,
                      style: TextStyle(
                          fontSize: 15, height: 1.6, color: Colors.grey[800]),
                    ),
                  ),
                  SizedBox(height: 24),
                  _buildSectionTitle(
                      'Requirements', Icons.checklist, Colors.orange.shade700),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.job.requirements,
                      style: TextStyle(
                          fontSize: 15, height: 1.6, color: Colors.grey[800]),
                    ),
                  ),
                  SizedBox(height: 40),
                  _isApplying
                      ? Center(child: CircularProgressIndicator())
                      : Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.shade600,
                                Colors.teal.shade400
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _applyForJob,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Apply Now',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ApplicationsScreen extends StatefulWidget {
  @override
  _ApplicationsScreenState createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  List<dynamic> _applications = [];
  bool _isLoading = true;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  void _loadApplications() async {
    setState(() => _isLoading = true);
    try {
      final apps = await _apiService.getApplications();
      setState(() {
        _applications = apps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load applications')),
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Applications',
            style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.purple.shade400],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _applications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No applications yet',
                          style: TextStyle(fontSize: 18, color: Colors.grey)),
                      SizedBox(height: 8),
                      Text('Start applying for jobs!',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _applications.length,
                  itemBuilder: (context, index) {
                    final app = _applications[index];
                    final status = app['status'] ?? 'pending';
                    final statusColor = _getStatusColor(status);

                    return Container(
                      margin: EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white, statusColor.withOpacity(0.1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: statusColor.withOpacity(0.3), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withOpacity(0.2),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(16),
                        leading: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.work, color: statusColor, size: 28),
                        ),
                        title: Text(
                          app['job_title'] ?? 'Unknown Job',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.grey[800],
                          ),
                        ),
                        subtitle: Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app['company'] ?? 'Unknown Company',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              SizedBox(height: 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing:
                            Icon(Icons.arrow_forward_ios, color: statusColor),
                      ),
                    );
                  },
                ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _email = '';
  String _fullName = '';
  String _location = '';
  String _dateOfBirth = '';
  String _graduationDate = '';
  String _graduationInstitution = '';
  String _transportationMode = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _email = prefs.getString('email') ?? 'No email';
      _fullName = prefs.getString('fullName') ?? 'No name';
      _location = prefs.getString('location') ?? 'No location';
      _graduationInstitution =
          prefs.getString('graduationInstitution') ?? 'No institution';
      _transportationMode =
          prefs.getString('transportationMode') ?? 'No transportation';

      final dobStr = prefs.getString('dateOfBirth');
      if (dobStr != null) {
        try {
          final dob = DateTime.parse(dobStr);
          _dateOfBirth = DateFormat('yyyy-MM-dd').format(dob);
        } catch (_) {
          _dateOfBirth = 'Not set';
        }
      } else {
        _dateOfBirth = 'Not set';
      }

      final gradStr = prefs.getString('graduationDate');
      if (gradStr != null) {
        try {
          final grad = DateTime.parse(gradStr);
          _graduationDate = DateFormat('yyyy-MM-dd').format(grad);
        } catch (_) {
          _graduationDate = 'Not set';
        }
      } else {
        _graduationDate = 'Not set';
      }

      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.purple.shade400],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.purple.shade50],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(Icons.person,
                          size: 80, color: Colors.blue.shade700),
                    ),
                    SizedBox(height: 24),
                    Text(
                      _fullName,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _email,
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    SizedBox(height: 32),
                    _buildInfoCard(
                      icon: Icons.location_on,
                      title: 'Location',
                      value: _location,
                      color: Colors.red.shade400,
                    ),
                    _buildInfoCard(
                      icon: Icons.cake,
                      title: 'Date of Birth',
                      value: _dateOfBirth,
                      color: Colors.pink.shade400,
                    ),
                    _buildInfoCard(
                      icon: Icons.school,
                      title: 'Institution',
                      value: _graduationInstitution,
                      color: Colors.blue.shade600,
                    ),
                    _buildInfoCard(
                      icon: Icons.calendar_today,
                      title: 'Graduation Date',
                      value: _graduationDate,
                      color: Colors.purple.shade400,
                    ),
                    _buildInfoCard(
                      icon: Icons.directions_car,
                      title: 'Transportation',
                      value: _transportationMode,
                      color: Colors.green.shade600,
                    ),
                    SizedBox(height: 32),
                    // Sign Out Button
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade600],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _signOut,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Sign Out',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _signOut() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 8),
            Text('Sign Out'),
          ],
        ),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Clear auth token
      final apiService = ApiService();
      await apiService.clearToken();
      
      // Clear all stored data
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Navigate to login screen and remove all previous routes
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Successfully signed out'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Widget _buildInfoCard(
      {required IconData icon,
      required String title,
      required String value,
      required Color color}) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, color.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- SPLASH SCREEN ----------
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Wait a moment for splash effect
    await Future.delayed(Duration(seconds: 1));

    try {
      final isLoggedIn = await _apiService.isLoggedIn();
      
      if (isLoggedIn) {
        // User is logged in, go to home screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      } else {
        // No valid token, go to login screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    } catch (e) {
      // On error, go to login screen
      print('Authentication check error: $e');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade700,
              Colors.purple.shade500,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.work,
                size: 100,
                color: Colors.white,
              ),
              SizedBox(height: 24),
              Text(
                'Job Search App',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 16),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- MAIN APP ----------
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Job Search App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: SplashScreen(),
      routes: {
        '/login': (context) => LoginScreen(),
        '/signup': (context) => SignupScreen(),
        '/home': (context) => HomeScreen(),
      },
    );
  }
}
