import 'package:flutter/material.dart';
import '../services/subscription_service.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _loading = false;

  Future<void> _subscribe({required bool yearly}) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      // Simulate payment flow.
      final paymentService = MockPaymentService.instance;

      await paymentService.initializePayment({});
      await paymentService.createPaymentIntent(
        amount: yearly ? 39.90 : 4.90,
        currency: 'MYR',
        description: yearly
            ? 'CampusTrade Premium Yearly'
            : 'CampusTrade Premium Monthly',
      );

      // Activate premium in Firestore.
      await SubscriptionService.instance.activatePremium(yearly: yearly);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Premium subscription activated!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subscription failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Go Premium')),

      body: SingleChildScrollView(
        child: Column(
          children: [
            // ---- Hero Section ----
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade400, Colors.orange.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.verified_rounded,
                    size: 72,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Unlock Premium Features',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Get the most out of CampusTrade',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ---- Benefits ----
            _benefitCard(
              icon: Icons.all_inclusive,
              title: 'Unlimited Listings',
              subtitle:
                  'Sell as many items as you want with no restrictions.',
            ),
            _benefitCard(
              icon: Icons.trending_up_rounded,
              title: 'Boosted Marketplace Visibility',
              subtitle:
                  'Your listings appear first in search results for faster sales.',
            ),
            _benefitCard(
              icon: Icons.verified_rounded,
              title: 'Premium Seller Badge',
              subtitle:
                  'Stand out with a Premium Seller badge on all your listings.',
            ),
            _benefitCard(
              icon: Icons.insert_chart_outlined_rounded,
              title: 'Future Seller Analytics',
              subtitle:
                  'Get insights on your listings and track your sales performance.',
            ),

            const SizedBox(height: 32),

            // ---- Pricing ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Text(
                    'Choose Your Plan',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Monthly
                  _pricingCard(
                    title: 'Monthly',
                    price: 'RM4.90',
                    period: '/month',
                    onTap: () => _subscribe(yearly: false),
                  ),
                  const SizedBox(height: 12),

                  // Yearly
                  _pricingCard(
                    title: 'Yearly',
                    price: 'RM39.90',
                    period: '/year',
                    onTap: () => _subscribe(yearly: true),
                    isYearly: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _benefitCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.amber.shade50,
            child: Icon(icon, color: Colors.amber.shade700),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  Widget _pricingCard({
    required String title,
    required String price,
    required String period,
    required VoidCallback onTap,
    bool isYearly = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: _loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                          if (isYearly) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'SAVE 32%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            price,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              period,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 18,
                    color: AppColors.electricBlue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
