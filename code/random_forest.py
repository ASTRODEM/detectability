#!/usr/bin/python

from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import roc_curve, roc_auc_score
from pylab import *
import pandas as pd
import sys
import matplotlib.pyplot as plt
from sklearn.model_selection import train_test_split
import re

inputArgs = sys.argv
legends = [];
for i in inputArgs[1:]:
    label = re.sub('^.+\/(featurified_codes-)?([^/]+)\.\w+', '\\2', i)
    label = re.sub('codes', 'features', label)
    print(label)
    data_file = i;
    data = pd.read_csv(data_file)
    print(data.shape)

    features = data.drop(['patid'], axis=1);
    features = features.drop(['class'], axis=1);
    patients = data['patid'];
    classes  = data['class'];
    #print(list(features))

    X_train, X_test, y_train, y_test = train_test_split(features, classes, test_size=0.33, random_state=42);


    rf = RandomForestClassifier(n_estimators=100)
    rf.fit(X_train, y_train)
    preds = rf.predict_proba(X_test)

    fpr, tpr, thr = roc_curve(y_test, preds[:,1])
    auc = roc_auc_score(y_test, preds[:,1])
    plt.plot(fpr,tpr)
    name = label
    label += " (auc: " + str(round(auc, 3)) + ")"
    legends.append(label)
    plt.xlabel("False positive rate")
    plt.ylabel("True positive rate")


    fi = zip(rf.feature_importances_, list(features))
    fi = sorted(fi, reverse = True); # key=lambda x: -x[1])
    fi = pd.DataFrame(fi, columns=["Importance", "Feature"])
    fi.to_csv(path_or_buf='feature_weights_for_'+ name +'.txt', mode='w', header=1, index=0)
    #print(fi);


plt.legend(legends);
plt.savefig('plot.png');
