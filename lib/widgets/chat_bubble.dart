import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final String time;
  final String type;
  final String imageUrl;
  final String deliveryStatus;
  final VoidCallback? onImageTap;

  const ChatBubble({
    super.key,
    required this.isMe,
    required this.text,
    required this.time,
    this.type = 'text',
    this.imageUrl = '',
    this.deliveryStatus = '',
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    if (type == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final isImage = type == 'image' && imageUrl.isNotEmpty;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
      children: [
        Padding(
            padding: EdgeInsets.only(
              left: isMe ? 76 : 12,
              right: isMe ? 12 : 76,
              top: 3,
              bottom: 1,
            ),
            child: Container(
                constraints: const BoxConstraints(maxWidth: 248),
                padding: EdgeInsets.all(isImage ? 4 : 12),
                decoration: BoxDecoration(
                  color: isMe
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade200,
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
                child: isImage
                    ? GestureDetector(
                        onTap: onImageTap,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            width: 220,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const SizedBox(
                                width: 220,
                                height: 160,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 220,
                              height: 120,
                              child: Center(child: Icon(Icons.broken_image)),
                            ),
                          ),
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
        ),
        Padding(
            padding: EdgeInsets.only(
              left: isMe ? 76 : 16,
              right: isMe ? 16 : 76,
              bottom: 4,
            ),
          child: Text(
            [
              time,
              if (isMe && deliveryStatus.isNotEmpty) deliveryStatus,
            ].join(' | '),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
      ],
      ),
    );
  }
}
