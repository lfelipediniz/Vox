import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Animated,
  Modal,
} from 'react-native';

const FloatingButton: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const scaleAnim = useRef(new Animated.Value(1)).current;
  const fadeAnim = useRef(new Animated.Value(0)).current;

  const handlePressIn = () => {
    Animated.spring(scaleAnim, {
      toValue: 0.9,
      useNativeDriver: true,
    }).start();
  };

  const handlePressOut = () => {
    Animated.spring(scaleAnim, {
      toValue: 1,
      useNativeDriver: true,
    }).start();
  };

  const togglePopover = () => {
    if (!isOpen) {
      setIsOpen(true);
      Animated.timing(fadeAnim, {
        toValue: 1,
        duration: 200,
        useNativeDriver: true,
      }).start();
    } else {
      Animated.timing(fadeAnim, {
        toValue: 0,
        duration: 200,
        useNativeDriver: true,
      }).start(() => {
        setIsOpen(false);
      });
    }
  };

  return (
    <>
      <View style={styles.container}>
        <Animated.View
          style={[
            styles.buttonWrapper,
            { transform: [{ scale: scaleAnim }] },
          ]}
        >
          <TouchableOpacity
            style={styles.floatingButton}
            onPress={togglePopover}
            onPressIn={handlePressIn}
            onPressOut={handlePressOut}
            activeOpacity={0.8}
          >
            <Text style={styles.buttonIcon}>💬</Text>
          </TouchableOpacity>
        </Animated.View>
      </View>

      {isOpen && (
        <Modal
          transparent
          visible={isOpen}
          animationType="none"
          onRequestClose={togglePopover}
        >
          <TouchableOpacity
            style={styles.overlay}
            activeOpacity={1}
            onPress={togglePopover}
          >
            <Animated.View
              style={[
                styles.popoverContainer,
                { opacity: fadeAnim },
              ]}
            >
              <View style={styles.popover}>
                <Text style={styles.popoverText}>Falar com a IA</Text>
              </View>
            </Animated.View>
          </TouchableOpacity>
        </Modal>
      )}
    </>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: 20,
    right: 20,
    zIndex: 1000,
  },
  buttonWrapper: {
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 4,
    },
    shadowOpacity: 0.3,
    shadowRadius: 4.65,
    elevation: 8,
  },
  floatingButton: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#007AFF',
    justifyContent: 'center',
    alignItems: 'center',
  },
  buttonIcon: {
    fontSize: 28,
  },
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.3)',
    justifyContent: 'flex-end',
    alignItems: 'flex-end',
  },
  popoverContainer: {
    position: 'absolute',
    bottom: 90,
    right: 20,
  },
  popover: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 12,
    minWidth: 150,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  popoverText: {
    fontSize: 16,
    color: '#333',
    fontWeight: '500',
  },
});

export default FloatingButton;
