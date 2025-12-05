package com.example.sample;

import java.util.List;
import java.util.ArrayList;

public class SampleClass {
    private String name;
    private int count;

    public SampleClass(String name) {
        this.name = name;
        this.count = 0;
    }

    public void increment() {
        count++;
    }

    public int getCount() {
        return count;
    }

    public String getName() {
        return name;
    }

    public static List<String> processItems(List<String> items) {
        List<String> results = new ArrayList<>();
        for (String item : items) {
            results.add(item.toUpperCase());
        }
        return results;
    }
}