import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';

const _callControlChannel = MethodChannel('com.zentra.dialer/call_control');

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact>? _contacts;
  List<Contact>? _filteredContacts;
  Set<String> _favoriteIds = {};
  bool _permissionDenied = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchContacts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchContacts() async {
    if (!await FlutterContacts.requestPermission(readonly: false)) {
      setState(() => _permissionDenied = true);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList('favorites') ?? [];
    _favoriteIds = favList.toSet();

    final contacts = await FlutterContacts.getContacts(
        withProperties: true, withPhoto: true);
    setState(() {
      _contacts = contacts;
      _filteredContacts = contacts;
    });
  }

  Future<void> _toggleFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteIds.contains(id)) {
        _favoriteIds.remove(id);
      } else {
        _favoriteIds.add(id);
      }
    });
    await prefs.setStringList('favorites', _favoriteIds.toList());
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (_contacts == null) return;

    setState(() {
      _filteredContacts = _contacts!.where((c) {
        final nameMatches = c.displayName.toLowerCase().contains(query);
        final numberMatches =
            c.phones.any((p) => p.number.replaceAll(RegExp(r'\D'), '').contains(query));
        return nameMatches || numberMatches;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kSurface,
        appBar: AppBar(
          titleSpacing: 20,
          title: const Text('Contacts'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () async {
                await FlutterContacts.openExternalInsert();
                _fetchContacts();
              },
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(115),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search contacts...',
                      prefixIcon: const Icon(Icons.search_rounded, color: kTextSecondary),
                      filled: true,
                      fillColor: kCardBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: kPurple),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const TabBar(
                  indicatorColor: kPurple,
                  labelColor: kPurple,
                  unselectedLabelColor: kTextSecondary,
                  tabs: [
                    Tab(text: 'All Contacts'),
                    Tab(text: 'Favorites'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildList(showFavoritesOnly: false),
            _buildList(showFavoritesOnly: true),
          ],
        ),
      ),
    );
  }

  Widget _buildList({required bool showFavoritesOnly}) {
    if (_permissionDenied) {
      return const Center(child: Text('Permission denied'));
    }
    if (_contacts == null) {
      return const Center(
          child: CircularProgressIndicator(color: kPurpleDark, strokeWidth: 2));
    }
    final listToRender = showFavoritesOnly
        ? _filteredContacts!.where((c) => _favoriteIds.contains(c.id)).toList()
        : _filteredContacts!;

    if (listToRender.isEmpty) {
      return Center(
        child: Text(showFavoritesOnly ? 'No favorites yet' : 'No contacts found'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: listToRender.length,
      itemBuilder: (context, index) {
        final contact = listToRender[index];
        final photo = contact.photo;
        final isFav = _favoriteIds.contains(contact.id);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: kPurple.withOpacity(0.1),
            backgroundImage: photo != null ? MemoryImage(photo) : null,
            child: photo == null
                ? Text(contact.displayName.isNotEmpty ? contact.displayName[0] : '?',
                    style: const TextStyle(color: kPurpleDeep, fontWeight: FontWeight.bold))
                : null,
          ),
          title: Text(contact.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: contact.phones.isNotEmpty
              ? Text(contact.phones.first.number, style: const TextStyle(color: kTextSecondary))
              : null,
          trailing: IconButton(
            icon: Icon(
              isFav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isFav ? Colors.amber : Colors.grey,
            ),
            onPressed: () => _toggleFavorite(contact.id),
          ),
          onTap: () {
            _showContactSheet(context, contact);
          },
        );
      },
    );
  }

  void _showContactSheet(BuildContext context, Contact contact) {
    if (contact.phones.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              // Avatar
              CircleAvatar(
                radius: 40,
                backgroundColor: kPurple.withOpacity(0.1),
                backgroundImage: contact.photo != null ? MemoryImage(contact.photo!) : null,
                child: contact.photo == null
                    ? Text(contact.displayName.isNotEmpty ? contact.displayName[0] : '?',
                        style: const TextStyle(fontSize: 32, color: kPurpleDeep, fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                contact.displayName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BigActionBtn(
                    icon: Icons.call_rounded,
                    label: 'Call',
                    color: Colors.green,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final number = contact.phones.first.number;
                      try {
                        await _callControlChannel.invokeMethod('placeCall', {'number': number});
                      } catch (e) {
                        final uri = Uri(scheme: 'tel', path: number);
                        await launchUrl(uri);
                      }
                    },
                  ),
                  _BigActionBtn(
                    icon: Icons.message_rounded,
                    label: 'Message',
                    color: Colors.blue,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final uri = Uri(scheme: 'sms', path: contact.phones.first.number);
                      await launchUrl(uri);
                    },
                  ),
                  _BigActionBtn(
                    icon: Icons.edit_rounded,
                    label: 'Edit',
                    color: kPurpleDark,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await FlutterContacts.openExternalEdit(contact.id);
                      _fetchContacts();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

class _BigActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BigActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
