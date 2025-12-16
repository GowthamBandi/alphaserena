import 'package:flutter/material.dart';

class ClientChatScreen extends StatelessWidget {
  const ClientChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: const Text("Coach Arjun"),
            subtitle: const Text("Last message preview"),
          ),
          const Expanded(child: Center(child: Text("Chat UI goes here"))),
        ],
      ),
    );
  }
}
