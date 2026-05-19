import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final String time;
  final String type;
  final VoidCallback? onReviewTap;

  const ChatBubble({
    super.key,
    required this.isMe,
    required this.text,
    required this.time,
    this.type = 'text',
    this.onReviewTap,
  });

  @override
  Widget build(BuildContext context) {
    if (type == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (type == 'transaction_update') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horizontal_circle, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (type == 'rating_prompt') {
      return Center(
        child: InkWell(
          onTap: onReviewTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: type == 'image' ? EdgeInsets.zero : const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: type == 'image' 
                      ? Colors.transparent 
                      : (isMe ? Theme.of(context).primaryColor : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(16).copyWith(
                    bottomRight: isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                    bottomLeft: isMe
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: type == 'image'
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16).copyWith(
                          bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                          bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                        ),
                        child: Image.network(
                          text,
                          width: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox(
                              width: 200,
                              height: 200,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                        ),
                      )
                    : Text(
                        text,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 15,
                        ),
                      ),
              ),
            ],
          ),
        ),
        // Timestamp
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Text(
            time,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
      ],
    );
  }
}
