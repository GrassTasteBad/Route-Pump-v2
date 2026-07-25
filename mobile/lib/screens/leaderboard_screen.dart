import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? myStats;
  List<dynamic> leaderboard = [];

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    setState(() => _isLoading = true);

    if (AppState().isSandboxMode) {
      // Mock Sandbox Leaderboard data
      setState(() {
        myStats = {
          'rank': 3,
          'name': AppState().currentUser?['name'] ?? 'Demo Motorist',
          'trust_score': 85,
          'tier': 'Gold Reporter',
          'reports_count': 14,
          'is_current_user': true,
        };
        leaderboard = [
          {
            'rank': 1,
            'name': 'Maria Santos',
            'trust_score': 98,
            'tier': 'Platinum Reporter',
            'reports_count': 42,
            'is_current_user': false,
          },
          {
            'rank': 2,
            'name': 'Juan Dela Cruz',
            'trust_score': 91,
            'tier': 'Platinum Reporter',
            'reports_count': 29,
            'is_current_user': false,
          },
          {
            'rank': 3,
            'name': AppState().currentUser?['name'] ?? 'Demo Motorist',
            'trust_score': 85,
            'tier': 'Gold Reporter',
            'reports_count': 14,
            'is_current_user': true,
          },
          {
            'rank': 4,
            'name': 'Carlos Reyes',
            'trust_score': 74,
            'tier': 'Silver Reporter',
            'reports_count': 9,
            'is_current_user': false,
          },
          {
            'rank': 5,
            'name': 'Elena Torralba',
            'trust_score': 62,
            'tier': 'Silver Reporter',
            'reports_count': 5,
            'is_current_user': false,
          },
        ];
        _isLoading = false;
      });
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/leaderboard'),
        headers: AppState().getHeaders(),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          myStats = data['my_stats'];
          leaderboard = data['leaderboard'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Leaderboard error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getTierColor(String tier) {
    if (tier.contains('Platinum')) return const Color(0xFFE5E7EB);
    if (tier.contains('Gold')) return const Color(0xFFF59E0B);
    if (tier.contains('Silver')) return const Color(0xFF9CA3AF);
    return const Color(0xFFD97706);
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) return const Text('🥇', style: TextStyle(fontSize: 22));
    if (rank == 2) return const Text('🥈', style: TextStyle(fontSize: 22));
    if (rank == 3) return const Text('🥉', style: TextStyle(fontSize: 22));
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '#$rank',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Motorist Leaderboard', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchLeaderboard,
            tooltip: 'Refresh Leaderboard',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchLeaderboard,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Personal Trust Score Header Card
                  if (myStats != null)
                    Container(
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF059669).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            child: const Icon(Icons.workspace_premium_rounded, size: 36, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  myStats!['name'] ?? 'Motorist',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        myStats!['tier'] ?? 'Reporter',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${myStats!['reports_count']} reports',
                                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('TRUST SCORE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
                              Text(
                                '${myStats!['trust_score']}',
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                              Text(
                                'Rank #${myStats!['rank']}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.9)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  const Text(
                    'TOP COMMUNITY REPORTERS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 10),

                  // Leaderboard List Cards
                  ...leaderboard.map((item) {
                    final bool isMe = item['is_current_user'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFF059669).withValues(alpha: 0.08) : Colors.white,
                        border: Border.all(
                          color: isMe ? const Color(0xFF059669) : Colors.grey.withValues(alpha: 0.2),
                          width: isMe ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildRankBadge(item['rank']),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      item['name'],
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                                        color: isMe ? const Color(0xFF059669) : Colors.black87,
                                      ),
                                    ),
                                    if (isMe)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF059669),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('YOU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item['tier']} • ${item['reports_count']} price reports',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getTierColor(item['tier'] ?? '').withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 4),
                                Text(
                                  '${item['trust_score']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
