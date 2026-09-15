"""Regenerate assets/models/*.tflite from the face-api.js weights used by the web app.

The mobile face attendance screen must produce the same 128-d descriptors as the
web portal (@vladmandic/face-api), so the models are rebuilt layer-by-layer from
the original weight manifests (architecture mirrors face-api's
src/faceFeatureExtractor, src/faceProcessor and src/faceRecognitionNet).
Both models take raw RGB (0..255) and apply face-api's mean/255 normalisation.

Usage (TensorFlow 2.19, Python 3.12):
    python tool/build_face_models.py \
        ../wp_webapp/node_modules/@vladmandic/face-api/model assets/models

Writes ssd_mobilenetv1.tflite (face detector), face_landmark_68.tflite and
face_recognition.tflite (float16 weights). Float16 descriptors differ from
face-api.js by < 0.001 (euclidean); SSD boxes by < 0.3 px.
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


# ------------------------------------------------------ SSD MobileNet v1
# The web portal's face detector (src/ssdMobilenetv1). Output rows are
# (ymin, xmin, ymax, xmax, score) relative to the 512 input square; NMS and
# scaling back to image pixels run in lib/utils/ssd_face_decoder.dart.
SW = load_weights("ssd_mobilenetv1_model")
SSD_EPS = 0.0010000000474974513
PRIORS = SW["Output/extra_dim"].reshape(-1, 4)
P_SIZE0 = PRIORS[:, 2] - PRIORS[:, 0]
P_SIZE1 = PRIORS[:, 3] - PRIORS[:, 1]
P_CENTER0 = PRIORS[:, 0] + P_SIZE0 / 2
P_CENTER1 = PRIORS[:, 1] + P_SIZE1 / 2


def ssd_pointwise(x, prefix, idx, stride):
    out = tf.nn.conv2d(x, SW[f"{prefix}/Conv2d_{idx}_pointwise/weights"], stride, "SAME")
    out = out + SW[f"{prefix}/Conv2d_{idx}_pointwise/convolution_bn_offset"]
    return tf.clip_by_value(out, 0.0, 6.0)


def ssd_depthwise(x, idx, stride):
    p = f"MobilenetV1/Conv2d_{idx}_depthwise"
    out = tf.nn.depthwise_conv2d(x, SW[p + "/depthwise_weights"], [1, stride, stride, 1], "SAME")
    out = tf.nn.batch_normalization(
        out, SW[p + "/BatchNorm/moving_mean"], SW[p + "/BatchNorm/moving_variance"],
        SW[p + "/BatchNorm/beta"], SW[p + "/BatchNorm/gamma"], SSD_EPS)
    return tf.clip_by_value(out, 0.0, 6.0)


def ssd_box_predictor(x, idx):
    p = f"Prediction/BoxPredictor_{idx}"
    enc = tf.nn.conv2d(x, SW[p + "/BoxEncodingPredictor/weights"], 1, "SAME") + SW[p + "/BoxEncodingPredictor/biases"]
    cls = tf.nn.conv2d(x, SW[p + "/ClassPredictor/weights"], 1, "SAME") + SW[p + "/ClassPredictor/biases"]
    return tf.reshape(enc, [1, -1, 4]), tf.reshape(cls, [1, -1, 3])


@tf.function(input_signature=[tf.TensorSpec([1, 512, 512, 3], tf.float32, name="rgb")])
def ssd_net(x):
    x = x / 127.5 - 1.0
    out = ssd_pointwise(x, "MobilenetV1", 0, 2)
    conv11 = None
    for i in range(1, 14):
        out = ssd_depthwise(out, i, 2 if i in (2, 4, 6, 12) else 1)
        out = ssd_pointwise(out, "MobilenetV1", i, 1)
        if i == 11:
            conv11 = out
    c0 = ssd_pointwise(out, "Prediction", 0, 1)
    c1 = ssd_pointwise(c0, "Prediction", 1, 2)
    c2 = ssd_pointwise(c1, "Prediction", 2, 1)
    c3 = ssd_pointwise(c2, "Prediction", 3, 2)
    c4 = ssd_pointwise(c3, "Prediction", 4, 1)
    c5 = ssd_pointwise(c4, "Prediction", 5, 2)
    c6 = ssd_pointwise(c5, "Prediction", 6, 1)
    c7 = ssd_pointwise(c6, "Prediction", 7, 2)
    preds = [ssd_box_predictor(conv11, 0), ssd_box_predictor(out, 1), ssd_box_predictor(c1, 2),
             ssd_box_predictor(c3, 3), ssd_box_predictor(c5, 4), ssd_box_predictor(c7, 5)]
    enc = tf.concat([p[0] for p in preds], 1)[0]
    cls = tf.concat([p[1] for p in preds], 1)[0]
    div0 = tf.exp(enc[:, 2] / 5) * P_SIZE0 / 2
    add0 = enc[:, 0] / 10 * P_SIZE0 + P_CENTER0
    div1 = tf.exp(enc[:, 3] / 5) * P_SIZE1 / 2
    add1 = enc[:, 1] / 10 * P_SIZE1 + P_CENTER1
    scores = tf.sigmoid(cls[:, 1])
    return tf.stack([add0 - div0, add1 - div1, add0 + div0, add1 + div1, scores], axis=1)[None]


def export(fn, name):
    converter = tf.lite.TFLiteConverter.from_concrete_functions([fn.get_concrete_function()], fn)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    path = os.path.join(OUT_DIR, f"{name}.tflite")
    open(path, "wb").write(converter.convert())
    print("wrote", path)


export(ssd_net, "ssd_mobilenetv1")
export(landmark_net, "face_landmark_68")
export(recognition_net, "face_recognition")
