import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';

const String _chatApiBaseUrl = 'https://blackforest.vseyal.com/api';
const Duration _chatPollInterval = Duration(seconds: 20);
const int _maxChatAttachmentBytes = 50 * 1024 * 1024;
const List<String> _chatAttachmentExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'heic',
  'heif',
  'mp4',
  'mov',
  'm4v',
  '3gp',
  'webm',
  'mkv',
  'avi',
  'mpeg',
  'mpg',
];

class AdminChatPage extends StatefulWidget {
  const AdminChatPage({super.key});

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;
  List<_ChatEmployee> _employees = const [];

  @override
  void initState() {
    super.initState();
    _loadEmployeesAndThreads();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeesAndThreads({bool showLoader = true}) async {
    if (mounted) {
      setState(() {
        if (showLoader) {
          _isLoading = true;
        }
        _isRefreshing = true;
        _loadError = null;
      });
    }

    try {
      final token = await _readToken();

      final responses = await Future.wait([
        http.get(
          Uri.parse('$_chatApiBaseUrl/users?limit=3000&depth=1&sort=name'),
          headers: _authHeaders(token),
        ),
        http.get(
          Uri.parse(
            '$_chatApiBaseUrl/message-threads?limit=3000&depth=0&sort=-updatedAt',
          ),
          headers: _authHeaders(token),
        ),
      ]);

      final usersResponse = responses[0];
      final threadsResponse = responses[1];

      if (usersResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(usersResponse, 'Unable to load employee users.'),
        );
      }

      if (threadsResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(threadsResponse, 'Unable to load chat threads.'),
        );
      }

      final userDocs =
          (_decodeResponse(usersResponse)?['docs'] as List?) ?? const [];
      final threadDocs =
          (_decodeResponse(threadsResponse)?['docs'] as List?) ?? const [];

      final Map<String, _MessageThreadSummary> threadsByStaffUser = {};
      for (final doc in threadDocs) {
        final thread = _MessageThreadSummary.fromJson(doc);
        if (thread == null) continue;
        threadsByStaffUser[thread.staffUserId] = thread;
      }

      final employees = <_ChatEmployee>[];
      for (final doc in userDocs) {
        final employee = _ChatEmployee.fromJson(doc);
        if (employee == null) continue;
        employees.add(
          employee.copyWith(thread: threadsByStaffUser[employee.userId]),
        );
      }

      employees.sort(
        (a, b) => a.employeeName.toLowerCase().compareTo(
          b.employeeName.toLowerCase(),
        ),
      );

      if (!mounted) return;
      setState(() {
        _employees = employees;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  List<_ChatEmployee> get _visibleEmployees {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _employees;

    return _employees.where((employee) {
      return employee.employeeName.toLowerCase().contains(query) ||
          employee.role.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openThread(_ChatEmployee employee) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _EmployeeChatThreadPage(
          employee: employee,
          initialThread: employee.thread,
        ),
      ),
    );

    if (!mounted) return;
    await _loadEmployeesAndThreads(showLoader: false);
  }

  @override
  Widget build(BuildContext context) {
    final employees = _visibleEmployees;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Employee Chats',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isRefreshing
                ? null
                : () => _loadEmployeesAndThreads(showLoader: false),
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search employee or role',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${employees.length} employee${employees.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'One thread per employee user',
                      style: TextStyle(fontSize: 13, color: Colors.black45),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(employees)),
        ],
      ),
    );
  }

  Widget _buildBody(List<_ChatEmployee> employees) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    if (_loadError != null && _employees.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 52,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isRefreshing
                    ? null
                    : () => _loadEmployeesAndThreads(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (employees.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadEmployeesAndThreads(showLoader: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'No employee users with login access were found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadEmployeesAndThreads(showLoader: false),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: employees.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final employee = employees[index];

          return Card(
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openThread(employee),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      child: Text(
                        employee.employeeName.isEmpty
                            ? '?'
                            : employee.employeeName.characters.first
                                  .toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            employee.employeeName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            employee.role.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.chevron_right, color: Colors.black45),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmployeeChatThreadPage extends StatefulWidget {
  final _ChatEmployee employee;
  final _MessageThreadSummary? initialThread;

  const _EmployeeChatThreadPage({required this.employee, this.initialThread});

  @override
  State<_EmployeeChatThreadPage> createState() =>
      _EmployeeChatThreadPageState();
}

class _EmployeeChatThreadPageState extends State<_EmployeeChatThreadPage>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _MessageThreadSummary? _thread;
  List<_ChatMessage> _messages = const [];
  List<_ChatMessage> _optimisticMessages = const [];
  Map<String, _MessageReceiptSummary> _receiptsByMessageId = const {};
  Timer? _pollTimer;
  bool _isBootstrapping = true;
  bool _isRefreshing = false;
  bool _hasDraft = false;
  bool _isSendingMessage = false;
  _PendingChatAttachment? _pendingAttachment;
  String? _loadError;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  int _localMessageSeed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageController.addListener(_handleComposerChange);
    _thread = widget.initialThread;
    _bootstrapConversation();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_handleComposerChange);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed && _thread != null) {
      _loadConversation(showLoader: false);
    }
  }

  void _handleComposerChange() {
    final nextHasDraft = _composerHasDraft;
    if (!mounted || nextHasDraft == _hasDraft) return;
    setState(() {
      _hasDraft = nextHasDraft;
    });
  }

  bool get _composerHasDraft =>
      _messageController.text.trim().isNotEmpty || _pendingAttachment != null;

  Future<void> _bootstrapConversation() async {
    if (mounted) {
      setState(() {
        _isBootstrapping = true;
        _loadError = null;
      });
    }

    try {
      final thread = await _ensureThread();
      if (!mounted) return;

      setState(() {
        _thread = thread;
      });

      await _loadConversation(showLoader: false, forceScrollToBottom: true);
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_chatPollInterval, (_) {
      _loadConversation(showLoader: false);
    });
  }

  Future<void> _pickAttachment() async {
    if (_isSendingMessage) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: _chatAttachmentExtensions,
        withData: true,
        withReadStream: !kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;
      final attachment = _PendingChatAttachment.fromPlatformFile(
        result.files.first,
      );

      if (attachment == null) {
        throw Exception('Only image and video files are allowed.');
      }

      if (attachment.size > _maxChatAttachmentBytes) {
        throw Exception('Selected file is larger than 50MB.');
      }

      if (!mounted) return;
      setState(() {
        _pendingAttachment = attachment;
        _hasDraft = _composerHasDraft;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _removePendingAttachment() {
    if (_pendingAttachment == null || !mounted) return;
    setState(() {
      _pendingAttachment = null;
      _hasDraft = _composerHasDraft;
    });
  }

  Future<void> _syncAdminFacingReceipts(
    String token,
    List<_MessageReceiptSummary> adminReceipts,
  ) async {
    if (adminReceipts.isEmpty ||
        _appLifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final deliverableReceipts = adminReceipts
        .where(
          (receipt) =>
              receipt.recipientAudience == 'admins' && receipt.status == 'sent',
        )
        .toList();

    await _updateReceiptStatuses(token, deliverableReceipts, 'delivered');

    final readableReceipts = adminReceipts
        .where(
          (receipt) =>
              receipt.recipientAudience == 'admins' && receipt.status != 'read',
        )
        .toList();

    await _updateReceiptStatuses(token, readableReceipts, 'read');
  }

  Future<void> _updateReceiptStatuses(
    String token,
    List<_MessageReceiptSummary> receipts,
    String nextStatus,
  ) async {
    if (receipts.isEmpty) return;

    final updates = <Future<void>>[];
    for (final receipt in receipts) {
      if (!_canMoveReceiptToStatus(receipt.status, nextStatus)) continue;
      updates.add(_patchReceiptStatus(token, receipt.id, nextStatus));
    }

    if (updates.isNotEmpty) {
      await Future.wait(updates);
    }
  }

  bool _canMoveReceiptToStatus(String currentStatus, String nextStatus) {
    return _statusRank(nextStatus) > _statusRank(currentStatus);
  }

  int _statusRank(String status) {
    switch (status) {
      case 'read':
        return 2;
      case 'delivered':
        return 1;
      default:
        return 0;
    }
  }

  Future<void> _patchReceiptStatus(
    String token,
    String receiptId,
    String nextStatus,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$_chatApiBaseUrl/message-receipts/$receiptId'),
        headers: _authHeaders(token, json: true),
        body: jsonEncode({'status': nextStatus}),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint(
          'Failed to update receipt $receiptId to $nextStatus: ${response.statusCode}',
        );
      }
    } catch (error) {
      debugPrint('Failed to update receipt $receiptId to $nextStatus: $error');
    }
  }

  Future<_MessageThreadSummary?> _fetchThreadByStaffUser(String token) async {
    final response = await http.get(
      Uri.parse(
        '$_chatApiBaseUrl/message-threads?limit=1&depth=0&where[staffUser][equals]=${widget.employee.userId}',
      ),
      headers: _authHeaders(token),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(response, 'Unable to look up the chat thread.'),
      );
    }

    final docs = (_decodeResponse(response)?['docs'] as List?) ?? const [];
    if (docs.isEmpty) return null;
    return _MessageThreadSummary.fromJson(docs.first);
  }

  Future<_MessageThreadSummary> _ensureThreadOpen(
    String token,
    _MessageThreadSummary thread,
  ) async {
    if (thread.status == 'open') {
      return thread;
    }

    final response = await http.patch(
      Uri.parse('$_chatApiBaseUrl/message-threads/${thread.id}'),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'status': 'open'}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _responseMessage(response, 'Unable to open this chat thread.'),
      );
    }

    final reopenedThread =
        _MessageThreadSummary.fromJson(_decodeResponse(response)) ??
        await _fetchThreadByStaffUser(token);

    if (reopenedThread == null) {
      throw Exception('Chat thread was reopened, but could not be loaded.');
    }

    return reopenedThread;
  }

  Future<_MessageThreadSummary> _ensureThread() async {
    final token = await _readToken();
    final existingThread = await _fetchThreadByStaffUser(token);
    if (existingThread != null) {
      return _ensureThreadOpen(token, existingThread);
    }

    final createResponse = await http.post(
      Uri.parse('$_chatApiBaseUrl/message-threads'),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'staffUser': widget.employee.userId}),
    );

    if (createResponse.statusCode == 200 || createResponse.statusCode == 201) {
      final createdThread =
          _MessageThreadSummary.fromJson(_decodeResponse(createResponse)) ??
          await _fetchThreadByStaffUser(token);
      if (createdThread != null) {
        return _ensureThreadOpen(token, createdThread);
      }
      throw Exception(
        'Chat thread was created, but the response could not be parsed.',
      );
    }

    final createError = _responseMessage(
      createResponse,
      'Unable to create the chat thread.',
    );
    if (createError.toLowerCase().contains('already has a message thread')) {
      final retryThread = await _fetchThreadByStaffUser(token);
      if (retryThread != null) {
        return _ensureThreadOpen(token, retryThread);
      }
    }

    throw Exception(createError);
  }

  Future<void> _loadConversation({
    bool showLoader = true,
    bool forceScrollToBottom = false,
  }) async {
    final thread = _thread;
    if (thread == null) return;

    final previousMessageCount = _buildDisplayMessages().length;
    final wasNearBottom = _isNearBottom();

    if (mounted) {
      setState(() {
        if (showLoader) {
          _isBootstrapping = true;
        }
        _isRefreshing = true;
        _loadError = null;
      });
    }

    try {
      final token = await _readToken();

      final responses = await Future.wait([
        http.get(
          Uri.parse(
            '$_chatApiBaseUrl/messages?limit=500&depth=1&sort=seq&where[thread][equals]=${thread.id}',
          ),
          headers: _authHeaders(token),
        ),
        http.get(
          Uri.parse(
            '$_chatApiBaseUrl/message-receipts?limit=500&depth=0&where[thread][equals]=${thread.id}&where[recipientAudience][equals]=staff',
          ),
          headers: _authHeaders(token),
        ),
        http.get(
          Uri.parse(
            '$_chatApiBaseUrl/message-receipts?limit=500&depth=0&where[thread][equals]=${thread.id}&where[recipientAudience][equals]=admins',
          ),
          headers: _authHeaders(token),
        ),
      ]);

      final messagesResponse = responses[0];
      final receiptsResponse = responses[1];
      final adminReceiptsResponse = responses[2];

      if (messagesResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(messagesResponse, 'Unable to load messages.'),
        );
      }

      if (receiptsResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(receiptsResponse, 'Unable to load message status.'),
        );
      }

      if (adminReceiptsResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(
            adminReceiptsResponse,
            'Unable to load admin receipt status.',
          ),
        );
      }

      final messageDocs =
          (_decodeResponse(messagesResponse)?['docs'] as List?) ?? const [];
      final receiptDocs =
          (_decodeResponse(receiptsResponse)?['docs'] as List?) ?? const [];
      final adminReceiptDocs =
          (_decodeResponse(adminReceiptsResponse)?['docs'] as List?) ??
          const [];

      final messages = <_ChatMessage>[];
      for (final doc in messageDocs) {
        final message = _ChatMessage.fromJson(doc);
        if (message != null) {
          messages.add(message);
        }
      }

      final Map<String, _MessageReceiptSummary> receiptsByMessageId = {};
      for (final doc in receiptDocs) {
        final receipt = _MessageReceiptSummary.fromJson(doc);
        if (receipt == null) continue;

        final existing = receiptsByMessageId[receipt.messageId];
        if (existing == null || receipt.rank > existing.rank) {
          receiptsByMessageId[receipt.messageId] = receipt;
        }
      }

      final adminReceipts = <_MessageReceiptSummary>[];
      for (final doc in adminReceiptDocs) {
        final receipt = _MessageReceiptSummary.fromJson(doc);
        if (receipt != null) {
          adminReceipts.add(receipt);
        }
      }

      if (!mounted) return;
      setState(() {
        _messages = messages;
        _optimisticMessages = _reconcileOptimisticMessages(
          _optimisticMessages,
          messages,
        );
        _receiptsByMessageId = receiptsByMessageId;
      });

      unawaited(_syncAdminFacingReceipts(token, adminReceipts));

      final shouldScroll =
          forceScrollToBottom ||
          previousMessageCount == 0 ||
          (_buildDisplayMessages().length > previousMessageCount &&
              wasNearBottom);
      if (shouldScroll) {
        _scrollToBottom();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
          _isRefreshing = false;
        });
      }
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final maxOffset = _scrollController.position.maxScrollExtent;
    return (maxOffset - _scrollController.offset) < 120;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  List<_ChatMessage> _buildDisplayMessages() {
    final merged = <_ChatMessage>[..._messages, ..._optimisticMessages];

    merged.sort((a, b) {
      final compare = a.createdAt.compareTo(b.createdAt);
      if (compare != 0) return compare;
      if (a.isLocalOnly == b.isLocalOnly) return 0;
      return a.isLocalOnly ? 1 : -1;
    });

    return merged;
  }

  List<_ChatMessage> _reconcileOptimisticMessages(
    List<_ChatMessage> optimisticMessages,
    List<_ChatMessage> actualMessages,
  ) {
    return optimisticMessages.where((optimisticMessage) {
      return !actualMessages.any(
        (actualMessage) =>
            _matchesOptimisticMessage(optimisticMessage, actualMessage),
      );
    }).toList();
  }

  bool _matchesOptimisticMessage(
    _ChatMessage optimisticMessage,
    _ChatMessage actualMessage,
  ) {
    if (!optimisticMessage.isLocalOnly || actualMessage.isLocalOnly) {
      return false;
    }

    if (optimisticMessage.threadId != actualMessage.threadId ||
        optimisticMessage.text != actualMessage.text) {
      return false;
    }

    if (optimisticMessage.messageType != actualMessage.messageType ||
        optimisticMessage.attachment != null ||
        actualMessage.attachment != null) {
      return false;
    }

    if (optimisticMessage.isFromAdmin != actualMessage.isFromAdmin) {
      return false;
    }

    final difference = optimisticMessage.createdAt
        .difference(actualMessage.createdAt)
        .inSeconds
        .abs();
    return difference <= 120;
  }

  void _removeOptimisticMessageById(String localMessageId) {
    if (!mounted) return;
    setState(() {
      _optimisticMessages = _optimisticMessages
          .where((message) => message.id != localMessageId)
          .toList();
    });
  }

  Future<String> _uploadAttachment(
    String token,
    _MessageThreadSummary thread,
    _PendingChatAttachment attachment,
  ) async {
    final uploadRequest =
        http.MultipartRequest(
            'POST',
            Uri.parse('$_chatApiBaseUrl/message-attachments'),
          )
          ..headers.addAll(_authHeaders(token))
          ..fields['_payload'] = jsonEncode({'thread': thread.id});

    if (attachment.bytes != null) {
      uploadRequest.files.add(
        http.MultipartFile.fromBytes(
          'file',
          attachment.bytes!,
          filename: attachment.fileName,
          contentType: attachment.mediaType,
        ),
      );
    } else if (attachment.readStream != null && attachment.size > 0) {
      uploadRequest.files.add(
        http.MultipartFile(
          'file',
          attachment.readStream!,
          attachment.size,
          filename: attachment.fileName,
          contentType: attachment.mediaType,
        ),
      );
    } else if (attachment.path != null &&
        attachment.path!.trim().isNotEmpty &&
        !attachment.path!.startsWith('content://')) {
      uploadRequest.files.add(
        await http.MultipartFile.fromPath(
          'file',
          attachment.path!,
          filename: attachment.fileName,
          contentType: attachment.mediaType,
        ),
      );
    } else {
      throw Exception('Selected file could not be read.');
    }

    final streamedResponse = await uploadRequest.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint(
        'Attachment upload failed: status=${response.statusCode}, body=${utf8.decode(response.bodyBytes)}',
      );
      throw Exception(
        _responseMessage(response, 'Unable to upload media attachment.'),
      );
    }

    final attachmentId = _relationshipId(_decodeResponse(response));
    if (attachmentId == null) {
      throw Exception('Attachment upload completed but no ID was returned.');
    }

    return attachmentId;
  }

  Future<void> _sendMessageInBackground(
    _MessageThreadSummary thread,
    String text, {
    _PendingChatAttachment? pendingAttachment,
    _ChatMessage? optimisticMessage,
  }) async {
    try {
      final token = await _readToken();
      String? attachmentId;
      if (pendingAttachment != null) {
        attachmentId = await _uploadAttachment(
          token,
          thread,
          pendingAttachment,
        );
      }

      final body = <String, dynamic>{'thread': thread.id};
      if (text.isNotEmpty) {
        body['text'] = text;
      }
      if (attachmentId != null) {
        body['attachment'] = attachmentId;
      }

      final response = await http.post(
        Uri.parse('$_chatApiBaseUrl/messages'),
        headers: _authHeaders(token, json: true),
        body: jsonEncode(body),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          _responseMessage(response, 'Unable to send the message.'),
        );
      }

      final createdMessage = _ChatMessage.fromJson(_decodeResponse(response));

      if (!mounted) return;
      setState(() {
        if (optimisticMessage != null) {
          _optimisticMessages = _optimisticMessages
              .where((message) => message.id != optimisticMessage.id)
              .toList();
        }

        if (createdMessage != null) {
          if (!_messages.any((message) => message.id == createdMessage.id)) {
            _messages = [..._messages, createdMessage]
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          }
        }
      });

      unawaited(
        _loadConversation(showLoader: false, forceScrollToBottom: true),
      );
    } catch (error) {
      if (optimisticMessage != null) {
        _removeOptimisticMessageById(optimisticMessage.id);
      } else if (pendingAttachment != null && mounted) {
        setState(() {
          _pendingAttachment ??= pendingAttachment;
          if (_messageController.text.trim().isEmpty && text.isNotEmpty) {
            _messageController.text = text;
            _messageController.selection = TextSelection.collapsed(
              offset: _messageController.text.length,
            );
          }
          _hasDraft = _composerHasDraft;
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final thread = _thread;
    final text = _messageController.text.trim();
    final pendingAttachment = _pendingAttachment;

    if (thread == null ||
        thread.status != 'open' ||
        (text.isEmpty && pendingAttachment == null) ||
        _isSendingMessage) {
      return;
    }

    FocusScope.of(context).unfocus();
    final optimisticMessage = pendingAttachment == null
        ? _ChatMessage(
            id: 'local-${_localMessageSeed++}',
            threadId: thread.id,
            senderRole: 'admin',
            text: text,
            createdAt: DateTime.now(),
            messageType: 'text',
            attachment: null,
            isLocalOnly: true,
          )
        : null;

    _messageController.clear();

    if (!mounted) return;
    setState(() {
      _pendingAttachment = null;
      _isSendingMessage = true;
      _hasDraft = false;

      if (optimisticMessage != null) {
        _optimisticMessages = [..._optimisticMessages, optimisticMessage];
      }
    });
    if (optimisticMessage != null) {
      _scrollToBottom();
    }

    unawaited(
      _sendMessageInBackground(
        thread,
        text,
        pendingAttachment: pendingAttachment,
        optimisticMessage: optimisticMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;

    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              child: Text(
                widget.employee.employeeName.isEmpty
                    ? '?'
                    : widget.employee.employeeName.characters.first
                          .toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.employee.employeeName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Call',
            onPressed: () {},
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildConversationBody()),
          if (thread != null)
            _Composer(
              controller: _messageController,
              isEnabled: thread.status == 'open',
              showSend: _hasDraft,
              isSending: _isSendingMessage,
              pendingAttachment: _pendingAttachment,
              onPickAttachment: _pickAttachment,
              onRemoveAttachment: _removePendingAttachment,
              onPrimaryAction: _hasDraft ? _sendMessage : _noopAction,
              disabledMessage: thread.status == 'open'
                  ? null
                  : 'This chat is unavailable right now.',
            )
          else if (_isBootstrapping)
            const _ChatStatusBar(message: 'Preparing chat...')
          else if (_loadError == null)
            const _ChatStatusBar(message: 'Creating chat thread...'),
        ],
      ),
    );
  }

  Widget _buildConversationBody() {
    final displayMessages = _buildDisplayMessages();

    if (_isBootstrapping && displayMessages.isEmpty) {
      return const _ConversationWallpaper(
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF075E54)),
        ),
      );
    }

    if (_loadError != null && displayMessages.isEmpty) {
      return _ConversationWallpaper(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 52,
                    color: Colors.black45,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isRefreshing ? null : _bootstrapConversation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF075E54),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (displayMessages.isEmpty) {
      return _ConversationWallpaper(
        child: RefreshIndicator(
          color: const Color(0xFF075E54),
          onRefresh: () => _loadConversation(showLoader: false),
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 140),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'No messages yet. Send the first message to start this conversation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _ConversationWallpaper(
      child: RefreshIndicator(
        color: const Color(0xFF075E54),
        onRefresh: () => _loadConversation(showLoader: false),
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
          itemCount: displayMessages.length,
          itemBuilder: (context, index) {
            final message = displayMessages[index];
            final previous = index > 0 ? displayMessages[index - 1] : null;
            final showDateChip =
                previous == null ||
                !_isSameCalendarDay(previous.createdAt, message.createdAt);

            return Column(
              children: [
                if (showDateChip) ...[
                  const SizedBox(height: 10),
                  _DateChip(date: message.createdAt),
                  const SizedBox(height: 8),
                ],
                _MessageBubble(
                  message: message,
                  receipt: _receiptsByMessageId[message.id],
                ),
                const SizedBox(height: 4),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool isEnabled;
  final bool showSend;
  final bool isSending;
  final _PendingChatAttachment? pendingAttachment;
  final VoidCallback onPickAttachment;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onPrimaryAction;
  final String? disabledMessage;

  const _Composer({
    required this.controller,
    required this.isEnabled,
    required this.showSend,
    required this.isSending,
    required this.pendingAttachment,
    required this.onPickAttachment,
    required this.onRemoveAttachment,
    required this.onPrimaryAction,
    this.disabledMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (disabledMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      disabledMessage!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            if (pendingAttachment != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 5,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      pendingAttachment!.isVideo
                          ? Icons.videocam_outlined
                          : Icons.image_outlined,
                      color: const Color(0xFF54656F),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${pendingAttachment!.fileName} • ${_formatFileSize(pendingAttachment!.size)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF33424A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: isEnabled && !isSending
                          ? onRemoveAttachment
                          : null,
                      color: const Color(0xFF54656F),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 54),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            enabled: isEnabled,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(
                                color: Color(0xFF667781),
                                fontSize: 17,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.fromLTRB(
                                18,
                                14,
                                10,
                                14,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: isEnabled && !isSending
                              ? onPickAttachment
                              : null,
                          icon: const Icon(
                            Icons.camera_alt_outlined,
                            color: Color(0xFF54656F),
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: const Color(0xFF00A884),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: isEnabled && !isSending ? onPrimaryAction : null,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(
                        child: isSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                showSend ? Icons.send_rounded : Icons.mic,
                                color: Colors.white,
                                size: showSend ? 24 : 28,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;

  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          _formatDateChipLabel(date),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF54656F),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final _MessageReceiptSummary? receipt;

  const _MessageBubble({required this.message, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final bool isOutgoing = message.isFromAdmin;
    final Color bubbleColor = isOutgoing
        ? const Color(0xFFD9FDD3)
        : Colors.white;
    const Color textColor = Color(0xFF111B21);
    const Color metaColor = Color(0xFF667781);
    final String status = receipt?.status ?? 'sent';
    final IconData? receiptIcon = isOutgoing
        ? (status == 'read' || status == 'delivered'
              ? Icons.done_all
              : Icons.done)
        : null;
    final Color receiptColor = status == 'read'
        ? const Color(0xFF53BDEB)
        : const Color(0xFF8696A0);
    final hasText = message.text.trim().isNotEmpty;
    final attachment = message.attachment;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(540, MediaQuery.of(context).size.width * 0.8),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(8),
              topRight: const Radius.circular(8),
              bottomLeft: Radius.circular(isOutgoing ? 8 : 2),
              bottomRight: Radius.circular(isOutgoing ? 2 : 8),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attachment != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: hasText ? 8 : 6),
                    child: _MessageAttachmentPreview(attachment: attachment),
                  ),
                if (hasText)
                  Padding(
                    padding: const EdgeInsets.only(right: 54, bottom: 2),
                    child: Text(
                      message.text,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.28,
                        color: textColor,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(message.createdAt.toLocal()),
                        style: const TextStyle(fontSize: 12, color: metaColor),
                      ),
                      if (receiptIcon != null) ...[
                        const SizedBox(width: 3),
                        Icon(receiptIcon, size: 16, color: receiptColor),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageAttachmentPreview extends StatelessWidget {
  final _ChatAttachment attachment;

  const _MessageAttachmentPreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final mimeType = attachment.mimeType.toLowerCase();
    final attachmentType = attachment.attachmentType.toLowerCase();
    final isImage = attachmentType == 'image' || mimeType.startsWith('image/');
    final mediaUrl = _resolveMediaUrl(attachment.url);

    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 240,
          height: 220,
          child: Image.network(
            mediaUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _mediaFallback(
              icon: Icons.broken_image_outlined,
              label: 'Image unavailable',
            ),
          ),
        ),
      );
    }

    return _mediaFallback(
      icon: Icons.videocam_outlined,
      label: 'Video attachment',
      subtitle: attachment.mimeType,
    );
  }

  Widget _mediaFallback({
    required IconData icon,
    required String label,
    String? subtitle,
  }) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF51616B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF33424A),
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5B6B74),
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

class _ChatStatusBar extends StatelessWidget {
  final String message;

  const _ChatStatusBar({required this.message});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF075E54),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF54656F),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFF00A884),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationWallpaper extends StatelessWidget {
  final Widget child;

  const _ConversationWallpaper({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFECE5DD)),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _WhatsAppWallpaperPainter()),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _WhatsAppWallpaperPainter extends CustomPainter {
  const _WhatsAppWallpaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = const Color(0xFFDDD5C8).withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final fillPaint = Paint()
      ..color = const Color(0xFFEEE6D9).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    const step = 72.0;
    for (double y = -20; y < size.height + step; y += step) {
      for (double x = -20; x < size.width + step; x += step) {
        final seed = ((x / step).round() + (y / step).round()) % 6;
        final offset = Offset(x + (seed * 5), y + ((seed + 2) * 3));
        switch (seed) {
          case 0:
            _paintCircleDoodle(canvas, offset, strokePaint, fillPaint);
            break;
          case 1:
            _paintRoundedSquare(canvas, offset, strokePaint);
            break;
          case 2:
            _paintTriangle(canvas, offset, strokePaint);
            break;
          case 3:
            _paintLeaf(canvas, offset, strokePaint);
            break;
          case 4:
            _paintStar(canvas, offset, strokePaint);
            break;
          default:
            _paintPhoneDoodle(canvas, offset, strokePaint);
        }
      }
    }
  }

  void _paintCircleDoodle(
    Canvas canvas,
    Offset offset,
    Paint strokePaint,
    Paint fillPaint,
  ) {
    final rect = Rect.fromCenter(center: offset, width: 24, height: 24);
    canvas.drawOval(rect, fillPaint);
    canvas.drawOval(rect, strokePaint);
    canvas.drawArc(rect.deflate(6), 0.3, math.pi * 0.9, false, strokePaint);
  }

  void _paintRoundedSquare(Canvas canvas, Offset offset, Paint strokePaint) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: offset, width: 20, height: 20),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, strokePaint);
    canvas.drawLine(
      offset.translate(-5, 0),
      offset.translate(5, 0),
      strokePaint,
    );
  }

  void _paintTriangle(Canvas canvas, Offset offset, Paint strokePaint) {
    final path = Path()
      ..moveTo(offset.dx, offset.dy - 10)
      ..lineTo(offset.dx - 10, offset.dy + 8)
      ..lineTo(offset.dx + 10, offset.dy + 8)
      ..close();
    canvas.drawPath(path, strokePaint);
  }

  void _paintLeaf(Canvas canvas, Offset offset, Paint strokePaint) {
    final rect = Rect.fromCenter(center: offset, width: 24, height: 14);
    canvas.drawArc(rect, 0, math.pi, false, strokePaint);
    canvas.drawArc(rect, math.pi, math.pi, false, strokePaint);
    canvas.drawLine(
      offset.translate(0, -7),
      offset.translate(0, 7),
      strokePaint,
    );
  }

  void _paintStar(Canvas canvas, Offset offset, Paint strokePaint) {
    canvas.drawLine(
      offset.translate(-8, 0),
      offset.translate(8, 0),
      strokePaint,
    );
    canvas.drawLine(
      offset.translate(0, -8),
      offset.translate(0, 8),
      strokePaint,
    );
    canvas.drawLine(
      offset.translate(-6, -6),
      offset.translate(6, 6),
      strokePaint,
    );
    canvas.drawLine(
      offset.translate(-6, 6),
      offset.translate(6, -6),
      strokePaint,
    );
  }

  void _paintPhoneDoodle(Canvas canvas, Offset offset, Paint strokePaint) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: offset, width: 14, height: 24),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, strokePaint);
    canvas.drawCircle(offset.translate(0, 7), 1.3, strokePaint);
    canvas.drawLine(
      offset.translate(-3, -7),
      offset.translate(3, -7),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChatEmployee {
  final String userId;
  final String employeeId;
  final String employeeName;
  final String role;
  final _MessageThreadSummary? thread;

  const _ChatEmployee({
    required this.userId,
    required this.employeeId,
    required this.employeeName,
    required this.role,
    this.thread,
  });

  static _ChatEmployee? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final userId = _relationshipId(json);
    final employee = json['employee'];
    final employeeId = _relationshipId(employee);
    final employeeName =
        _stringValue(
          employee is Map<String, dynamic> ? employee['name'] : null,
        ) ??
        _stringValue(json['name']) ??
        _stringValue(json['email']);

    if (userId == null || employeeId == null || employeeName == null) {
      return null;
    }

    return _ChatEmployee(
      userId: userId,
      employeeId: employeeId,
      employeeName: employeeName,
      role: _stringValue(json['role']) ?? '',
      thread: null,
    );
  }

  _ChatEmployee copyWith({_MessageThreadSummary? thread}) {
    return _ChatEmployee(
      userId: userId,
      employeeId: employeeId,
      employeeName: employeeName,
      role: role,
      thread: thread,
    );
  }
}

class _MessageThreadSummary {
  final String id;
  final String staffUserId;
  final String employeeId;
  final String participantName;
  final String status;
  final String? lastMessageText;
  final DateTime? lastMessageAt;

  const _MessageThreadSummary({
    required this.id,
    required this.staffUserId,
    required this.employeeId,
    required this.participantName,
    required this.status,
    required this.lastMessageText,
    required this.lastMessageAt,
  });

  static _MessageThreadSummary? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final id = _relationshipId(json);
    final staffUserId = _relationshipId(json['staffUser']);
    final employeeId = _relationshipId(json['employee']);
    if (id == null || staffUserId == null || employeeId == null) return null;

    return _MessageThreadSummary(
      id: id,
      staffUserId: staffUserId,
      employeeId: employeeId,
      participantName: _stringValue(json['participantName']) ?? '',
      status: _stringValue(json['status']) ?? 'open',
      lastMessageText: _stringValue(json['lastMessageText']),
      lastMessageAt: _parseDate(json['lastMessageAt']),
    );
  }
}

class _ChatMessage {
  final String id;
  final String threadId;
  final String senderRole;
  final String messageType;
  final String text;
  final _ChatAttachment? attachment;
  final DateTime createdAt;
  final bool isLocalOnly;

  const _ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderRole,
    required this.messageType,
    required this.text,
    required this.attachment,
    required this.createdAt,
    this.isLocalOnly = false,
  });

  bool get isFromAdmin => senderRole == 'admin' || senderRole == 'superadmin';

  static _ChatMessage? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final id = _relationshipId(json);
    final threadId = _relationshipId(json['thread']);
    final createdAt = _parseDate(json['createdAt']);
    final attachment = _ChatAttachment.fromJson(json['attachment']);
    final messageType =
        _stringValue(json['messageType']) ??
        (attachment != null ? attachment.attachmentType : 'text');
    final text = _stringValue(json['text']) ?? '';

    if (id == null || threadId == null || createdAt == null) {
      return null;
    }

    return _ChatMessage(
      id: id,
      threadId: threadId,
      senderRole: _stringValue(json['senderRole']) ?? '',
      messageType: messageType,
      text: text,
      attachment: attachment,
      createdAt: createdAt,
      isLocalOnly: false,
    );
  }
}

class _ChatAttachment {
  final String? id;
  final String url;
  final String mimeType;
  final String attachmentType;

  const _ChatAttachment({
    required this.id,
    required this.url,
    required this.mimeType,
    required this.attachmentType,
  });

  bool get isVideo =>
      attachmentType.toLowerCase() == 'video' ||
      mimeType.toLowerCase().startsWith('video/');

  static _ChatAttachment? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final url = _stringValue(json['url']);
    final mimeType = _stringValue(json['mimeType']);
    final attachmentType = _stringValue(json['attachmentType']);
    if (url == null || mimeType == null || attachmentType == null) {
      return null;
    }

    return _ChatAttachment(
      id: _relationshipId(json),
      url: url,
      mimeType: mimeType,
      attachmentType: attachmentType,
    );
  }
}

class _PendingChatAttachment {
  final String fileName;
  final String? path;
  final Uint8List? bytes;
  final Stream<List<int>>? readStream;
  final int size;
  final String mimeType;
  final MediaType mediaType;

  const _PendingChatAttachment({
    required this.fileName,
    required this.path,
    required this.bytes,
    required this.readStream,
    required this.size,
    required this.mimeType,
    required this.mediaType,
  });

  bool get isVideo => mimeType.toLowerCase().startsWith('video/');

  static _PendingChatAttachment? fromPlatformFile(PlatformFile file) {
    final name = file.name.trim();
    if (name.isEmpty) return null;

    final inferredMimeType =
        lookupMimeType(name, headerBytes: file.bytes) ??
        lookupMimeType(name.toLowerCase());

    if (inferredMimeType == null ||
        (!inferredMimeType.startsWith('image/') &&
            !inferredMimeType.startsWith('video/'))) {
      return null;
    }

    final parsedMediaType = MediaType.parse(inferredMimeType);
    final derivedSize = file.size > 0 ? file.size : (file.bytes?.length ?? 0);

    return _PendingChatAttachment(
      fileName: name,
      path: kIsWeb ? null : file.path,
      bytes: file.bytes,
      readStream: file.readStream,
      size: derivedSize,
      mimeType: inferredMimeType,
      mediaType: parsedMediaType,
    );
  }
}

class _MessageReceiptSummary {
  final String id;
  final String messageId;
  final String recipientAudience;
  final String status;

  const _MessageReceiptSummary({
    required this.id,
    required this.messageId,
    required this.recipientAudience,
    required this.status,
  });

  int get rank {
    switch (status) {
      case 'read':
        return 2;
      case 'delivered':
        return 1;
      default:
        return 0;
    }
  }

  static _MessageReceiptSummary? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final id = _relationshipId(json);
    final messageId = _relationshipId(json['message']);
    final recipientAudience = _stringValue(json['recipientAudience']);
    final status = _stringValue(json['status']);
    if (id == null ||
        messageId == null ||
        recipientAudience == null ||
        status == null) {
      return null;
    }

    return _MessageReceiptSummary(
      id: id,
      messageId: messageId,
      recipientAudience: recipientAudience,
      status: status,
    );
  }
}

Future<String> _readToken() async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'token');
  if (token == null || token.isEmpty) {
    throw Exception('Session expired. Please log in again.');
  }
  return token;
}

Map<String, String> _authHeaders(String token, {bool json = false}) {
  return {
    'Authorization': 'Bearer $token',
    if (json) 'Content-Type': 'application/json',
  };
}

Map<String, dynamic>? _decodeResponse(http.Response response) {
  final rawBody = utf8.decode(response.bodyBytes);
  if (rawBody.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(rawBody);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String _responseMessage(http.Response response, String fallback) {
  final decoded = _decodeResponse(response);
  if (decoded == null) return '$fallback (${response.statusCode})';

  final extracted = _extractMessageRecursive(decoded);
  if (extracted != null) {
    return extracted;
  }

  return '$fallback (${response.statusCode})';
}

String? _extractMessageRecursive(dynamic value) {
  if (value == null) return null;

  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (value is Map<String, dynamic>) {
    for (final key in const ['message', 'detail', 'error', 'reason']) {
      final nested = _extractMessageRecursive(value[key]);
      if (nested != null) return nested;
    }

    for (final entry in value.entries) {
      if (entry.key == 'stack' || entry.key == 'name') continue;
      final nested = _extractMessageRecursive(entry.value);
      if (nested != null) return nested;
    }

    return null;
  }

  if (value is List) {
    for (final item in value) {
      final nested = _extractMessageRecursive(item);
      if (nested != null) return nested;
    }
  }

  return null;
}

String? _relationshipId(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }

  if (value is Map<String, dynamic>) {
    final id = value['id'] ?? value['_id'];
    if (id is String && id.trim().isNotEmpty) {
      return id;
    }
  }

  return null;
}

String? _stringValue(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

DateTime? _parseDate(dynamic value) {
  final stringValue = _stringValue(value);
  if (stringValue == null) return null;
  return DateTime.tryParse(stringValue);
}

String _resolveMediaUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return trimmed;
  return Uri.parse('$_chatApiBaseUrl/').resolve(trimmed).toString();
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDateChipLabel(DateTime dateTime) {
  final local = dateTime.toLocal();
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfTarget = DateTime(local.year, local.month, local.day);
  final difference = startOfToday.difference(startOfTarget).inDays;

  if (difference == 0) {
    return 'Today';
  }

  if (difference == 1) {
    return 'Yesterday';
  }

  if (difference > 1 && difference < 7) {
    return DateFormat('EEEE').format(local);
  }

  return DateFormat('d MMMM yyyy').format(local);
}

bool _isSameCalendarDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

void _noopAction() {}
