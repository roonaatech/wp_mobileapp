"""Regenerate assets/models/*.tflite from the face-api.js weights used by the web app.

The mobile face attendance screen must produce the same 128-d descriptors as the
web portal (@vladmandic/face-api), so the models are rebuilt layer-by-layer from
the original weight manifests (architecture mirrors face-api's
src/faceFeatureExtractor, src/faceProcessor and src/faceRecognitionNet).
Both models take raw RGB (0..255) and apply face-api's mean/255 normalisation.

Usage (TensorFlow 2.19, Python 3.12):
    python tool/build_face_models.py \
        ../wp_webapp/node_modules/@vladmandic/face-api/model assets/models

Writes face_landmark_68.tflite and face_recognition.tflite (float16 weights).
Float16 descriptors differ from face-api.js by < 0.001 (euclidean).
"""
import json
import os
import sys

import numpy as np
import tensorflow as tf

MODEL_DIR = sys.argv[1]
OUT_DIR = sys.argv[2]
os.makedirs(OUT_DIR, exist_ok=True)

MEAN_RGB = np.array([122.782, 117.001, 104.298], dtype=np.float32)


def load_weights(name):
    manifest = json.load(open(os.path.join(MODEL_DIR, f"{name}-weights_manifest.json")))
    weights = {}
    for group in manifest:
        buf = b"".join(open(os.path.join(MODEL_DIR, p), "rb").read() for p in group["paths"])
        offset = 0
        for w in group["weights"]:
            shape = w["shape"]
            n = int(np.prod(shape)) if shape else 1
            q = w.get("quantization")
            if q:
                qd = q["dtype"]
                if qd == "uint8":
                    raw = np.frombuffer(buf, dtype=np.uint8, count=n, offset=offset)
                    offset += n
                    vals = raw.astype(np.float32) * np.float32(q["scale"]) + np.float32(q["min"])
                elif qd == "uint16":
                    raw = np.frombuffer(buf, dtype=np.uint16, count=n, offset=offset)
                    offset += 2 * n
                    vals = raw.astype(np.float32) * np.float32(q["scale"]) + np.float32(q["min"])
                elif qd == "float16":
                    vals = np.frombuffer(buf, dtype=np.float16, count=n, offset=offset).astype(np.float32)
                    offset += 2 * n
                else:
                    raise ValueError(f"unsupported quantization {qd}")
            else:
                vals = np.frombuffer(buf, dtype=np.float32, count=n, offset=offset)
                offset += 4 * n
            weights[w["name"]] = np.ascontiguousarray(vals.reshape(shape), dtype=np.float32)
        assert offset == len(buf), (name, offset, len(buf))
    return weights


# ---------------------------------------------------------------- landmarks
LW = load_weights("face_landmark_68_model")


def sep_conv(x, p, stride):
    out = tf.nn.separable_conv2d(
        x, LW[p + "/depthwise_filter"], LW[p + "/pointwise_filter"], [1, stride, stride, 1], "SAME"
    )
    return out + LW[p + "/bias"]


def dense_block4(x, p, first=False):
    if first:
        out1 = tf.nn.relu(tf.nn.conv2d(x, LW[p + "/conv0/filters"], 2, "SAME") + LW[p + "/conv0/bias"])
    else:
        out1 = tf.nn.relu(sep_conv(x, p + "/conv0", 2))
    out2 = sep_conv(out1, p + "/conv1", 1)
    in3 = tf.nn.relu(out1 + out2)
    out3 = sep_conv(in3, p + "/conv2", 1)
    in4 = tf.nn.relu(out1 + (out2 + out3))
    out4 = sep_conv(in4, p + "/conv3", 1)
    return tf.nn.relu(out1 + (out2 + (out3 + out4)))


@tf.function(input_signature=[tf.TensorSpec([1, 112, 112, 3], tf.float32, name="rgb")])
def landmark_net(x):
    x = (x - MEAN_RGB) / 255.0
    out = dense_block4(x, "dense0", first=True)
    out = dense_block4(out, "dense1")
    out = dense_block4(out, "dense2")
    out = dense_block4(out, "dense3")
    out = tf.nn.avg_pool2d(out, 7, 2, "VALID")
    out = tf.reshape(out, [1, 256])
    return tf.matmul(out, LW["fc/weights"]) + LW["fc/bias"]


# -------------------------------------------------------------- recognition
RW = load_weights("face_recognition_model")


def conv_layer(x, p, stride, relu, padding="SAME"):
    out = tf.nn.conv2d(x, RW[p + "/conv/filters"], stride, padding) + RW[p + "/conv/bias"]
    out = out * RW[p + "/scale/weights"] + RW[p + "/scale/biases"]
    return tf.nn.relu(out) if relu else out


def residual(x, p):
    out = conv_layer(x, p + "/conv1", 1, True)
    out = conv_layer(out, p + "/conv2", 1, False)
    return tf.nn.relu(out + x)


def residual_down(x, p):
    out = conv_layer(x, p + "/conv1", 2, True, "VALID")
    out = conv_layer(out, p + "/conv2", 1, False)
    pooled = tf.nn.avg_pool2d(x, 2, 2, "VALID")
    if pooled.shape[1] != out.shape[1] or pooled.shape[2] != out.shape[2]:
        # face-api appends exactly one zero row (bottom) and one zero column (right)
        out = tf.pad(out, [[0, 0], [0, 1], [0, 1], [0, 0]])
    if pooled.shape[3] != out.shape[3]:
        # face-api concatenates zeros(pooled.shape) on the channel axis
        pooled = tf.pad(pooled, [[0, 0], [0, 0], [0, 0], [0, int(pooled.shape[3])]])
    return tf.nn.relu(pooled + out)


@tf.function(input_signature=[tf.TensorSpec([1, 150, 150, 3], tf.float32, name="rgb")])
def recognition_net(x):
    x = (x - MEAN_RGB) / 255.0
    out = conv_layer(x, "conv32_down", 2, True, "VALID")
    out = tf.nn.max_pool2d(out, 3, 2, "VALID")
    for p in ["conv32_1", "conv32_2", "conv32_3"]:
        out = residual(out, p)
    out = residual_down(out, "conv64_down")
    for p in ["conv64_1", "conv64_2", "conv64_3"]:
        out = residual(out, p)
    out = residual_down(out, "conv128_down")
    for p in ["conv128_1", "conv128_2"]:
        out = residual(out, p)
    out = residual_down(out, "conv256_down")
    for p in ["conv256_1", "conv256_2"]:
        out = residual(out, p)
    out = residual_down(out, "conv256_down_out")
    out = tf.reduce_mean(out, [1, 2])
    return tf.matmul(out, RW["fc"])


def export(fn, name):
    converter = tf.lite.TFLiteConverter.from_concrete_functions([fn.get_concrete_function()], fn)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    path = os.path.join(OUT_DIR, f"{name}.tflite")
    open(path, "wb").write(converter.convert())
    print("wrote", path)


export(landmark_net, "face_landmark_68")
export(recognition_net, "face_recognition")
