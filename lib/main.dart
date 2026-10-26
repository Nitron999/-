Positioned(
          top: 14,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C26).withOpacity(0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00FF87).withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Карта и маршрут',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${gpsDistanceKm.toStringAsFixed(2)} км (${gpsDistanceMeters.round()} м)',
                      style: const TextStyle(color: Color(0xFF00FF87), fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Кнопка с машинкой и надписью «навигатор» для открытия Яндекс.Карт
                    TextButton.icon(
                      onPressed: _openYandexMapsWithTraffic,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF60EFFF),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      icon: const Icon(Icons.directions_car_rounded, color: Color(0xFF60EFFF), size: 20),
                      label: const Text(
                        'навигатор',
                        style: TextStyle(color: Color(0xFF60EFFF), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: _clearRoute,
                      tooltip: 'Очистить маршрут',
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF4B2B)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
