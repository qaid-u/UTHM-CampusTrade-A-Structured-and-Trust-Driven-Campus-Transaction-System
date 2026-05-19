import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class ItemImage extends StatefulWidget {
  const ItemImage({
    super.key,
    required this.urls,
    this.paths = const [],
    this.storageBucket = '',
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.emptyLabel = 'NO IMAGE',
    this.errorLabel = 'IMAGE ERROR',
  });

  final List<String> urls;
  final List<String> paths;
  final String storageBucket;
  final double? height;
  final double? width;
  final BoxFit fit;
  final String emptyLabel;
  final String errorLabel;

  @override
  State<ItemImage> createState() => _ItemImageState();
}

class _ItemImageState extends State<ItemImage> {
  late List<String> _sources;
  int _index = 0;
  Future<String>? _urlFuture;

  @override
  void initState() {
    super.initState();
    _resetSources();
  }

  @override
  void didUpdateWidget(covariant ItemImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls) ||
        !listEquals(oldWidget.paths, widget.paths) ||
        oldWidget.storageBucket != widget.storageBucket) {
      _resetSources();
    }
  }

  void _resetSources() {
    _sources = {
      ...widget.urls
          .map((source) => source.trim())
          .where((source) => source.isNotEmpty),
      ...widget.paths
          .map((source) => source.trim())
          .where((source) => source.isNotEmpty),
    }.toList();
    _index = 0;
    _urlFuture = _sources.isEmpty ? null : _resolveCurrentSource();
  }

  Future<String> _resolveCurrentSource() {
    return StorageService.instance.downloadUrlFor(
      _sources[_index],
      bucket: widget.storageBucket,
    );
  }

  void _tryNext(Object error) {
    debugPrint('Item image failed: ${_sources[_index]} -> $error');

    if (_index + 1 >= _sources.length || !mounted) {
      return;
    }

    setState(() {
      _index++;
      _urlFuture = _resolveCurrentSource();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_urlFuture == null) {
      return _ImageLabel(
        label: widget.emptyLabel,
        height: widget.height,
        width: widget.width,
      );
    }

    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _LoadingImage(height: widget.height, width: widget.width);
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tryNext(snapshot.error ?? 'Empty resolved URL');
          });

          if (_index + 1 < _sources.length) {
            return _LoadingImage(height: widget.height, width: widget.width);
          }

          return _ImageLabel(
            label: widget.errorLabel,
            height: widget.height,
            width: widget.width,
          );
        }

        return CachedNetworkImage(
          imageUrl: snapshot.data!,
          height: widget.height,
          width: widget.width,
          fit: widget.fit,
          placeholder: (context, url) =>
              _LoadingImage(height: widget.height, width: widget.width),
          errorWidget: (context, url, error) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _tryNext(error);
            });

            if (_index + 1 < _sources.length) {
              return _LoadingImage(height: widget.height, width: widget.width);
            }

            return _ImageLabel(
              label: widget.errorLabel,
              height: widget.height,
              width: widget.width,
            );
          },
          fadeInDuration: const Duration(milliseconds: 250),
          fadeOutDuration: const Duration(milliseconds: 150),
        );
      },
    );
  }
}

class _LoadingImage extends StatelessWidget {
  const _LoadingImage({this.height, this.width});

  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      color: Colors.grey.shade200,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.electricBlue),
          ),
        ),
      ),
    );
  }
}

class _ImageLabel extends StatelessWidget {
  const _ImageLabel({required this.label, this.height, this.width});

  final String label;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: const BoxDecoration(gradient: AppGradients.blueSurface),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
